import secrets
from datetime import timedelta
from decimal import ROUND_HALF_UP, Decimal

from django.db import IntegrityError, transaction
from django.db.models import Avg, Sum
from django.http import Http404
from django.shortcuts import get_object_or_404
from django.utils import timezone

from core.exceptions import Conflict, DomainError, Forbidden, RateLimited
from core.geo import haversine_km
from core.metrics import service_day_start
from core.models import PlatformConfig, ServiceZone
from apps.captains.models import CaptainProfile, OnlineStatus
from apps.captains.services import describe_reasons, eligibility_reasons, update_location
from apps.notifications.services import notify
from apps.payments.models import Payment, PaymentStatus, PaymentType
from apps.payments.services import create_payment
from apps.rides import matching, pricing
from apps.promotions import services as promo_services
from apps.rides.models import (
    ACTIVE_STATUSES,
    IN_PROGRESS_STATUSES,
    CancelledBy,
    CaptainCancelReason,
    CustomerCancelReason,
    FeeStatus,
    OfferStatus,
    PaymentMethod,
    Rating,
    RidePaymentStatus,
    Ride,
    RideEvent,
    RideLocation,
    RideOffer,
    RideShareLink,
    RideStatus,
)
from apps.rides.state import transition
from apps.subscriptions import services as subscription_services
from apps.subscriptions.models import DueStatus, PlatformDue

CANCELLABLE = {RideStatus.REQUESTED, RideStatus.SEARCHING, RideStatus.ACCEPTED, RideStatus.CAPTAIN_ARRIVED}
# The rider sees the start PIN from booking until the trip starts.
PIN_VISIBLE_STATUSES = {RideStatus.SEARCHING, RideStatus.ACCEPTED, RideStatus.CAPTAIN_ARRIVED}


# ---------- customer side ----------

def _inside_service_area(config, latitude, longitude):
    """Inside the main service area, or inside any active extra zone."""
    main = haversine_km(latitude, longitude, config.service_area_latitude, config.service_area_longitude)
    if main <= float(config.service_area_radius_km):
        return True
    return any(zone.contains(latitude, longitude) for zone in ServiceZone.objects.filter(is_active=True))


def ensure_in_service_area(data, check_device=False):
    """Pickup and drop (and, when booking, the rider's own device) must be inside the service area."""
    config = PlatformConfig.load()
    if not config.restrict_to_service_area:
        return
    name = config.service_area_name
    if not _inside_service_area(config, data["pickup_latitude"], data["pickup_longitude"]):
        raise DomainError(f"Pickup is outside our service area. Rides are available only in {name}.", code="pickup_outside_service_area")
    if not _inside_service_area(config, data["drop_latitude"], data["drop_longitude"]):
        raise DomainError(f"Drop is outside our service area. Rides are available only in {name}.", code="drop_outside_service_area")
    if check_device:
        lat, lon = data.get("device_latitude"), data.get("device_longitude")
        if lat is None or lon is None:
            raise DomainError("We could not confirm your location. Turn on location access to book.", code="device_location_required")
        if not _inside_service_area(config, lat, lon):
            raise DomainError(f"You must be in {name} to book a ride, even for someone else.", code="booker_outside_service_area")


def estimate(data, customer=None):
    ensure_in_service_area(data)
    quote = pricing.quote(
        data["vehicle_type"],
        data["pickup_latitude"],
        data["pickup_longitude"],
        data["drop_latitude"],
        data["drop_longitude"],
    )
    discount = Decimal("0")
    if data.get("promo_code") and customer is not None:
        _, discount = promo_services.validate(customer, data["promo_code"], quote.fare)
    # Money is sent as strings (like the ride serializers), so clients never round it through floats.
    return {
        "vehicle_type": quote.vehicle_type,
        "distance_km": str(quote.distance_km),
        "duration_minutes": quote.duration_minutes,
        "fare": str(quote.fare),
        "discount": str(discount),
        "payable_fare": str(quote.fare - discount),
        "currency": "INR",
    }


def outstanding_fees(customer):
    """Cancelled rides whose fee the rider still owes."""
    return Ride.objects.filter(
        customer=customer, status=RideStatus.CANCELLED, cancellation_fee_status=FeeStatus.UNPAID
    )


def _new_start_pin():
    return f"{secrets.randbelow(10000):04d}"


def create_ride(customer, data, idempotency_key=None):
    if idempotency_key:
        existing = Ride.objects.filter(customer=customer, idempotency_key=idempotency_key).first()
        if existing is not None:
            return existing
    if Ride.objects.filter(customer=customer, status__in=ACTIVE_STATUSES).exists():
        raise Conflict("You already have an active ride.", code="active_ride_exists")
    if PlatformConfig.load().block_booking_on_unpaid_fees and outstanding_fees(customer).exists():
        raise Conflict("Please pay your pending cancellation fee to book again.", code="unpaid_cancellation_fee")
    ensure_in_service_area(data, check_device=True)

    quote = pricing.quote(
        data["vehicle_type"],
        data["pickup_latitude"],
        data["pickup_longitude"],
        data["drop_latitude"],
        data["drop_longitude"],
    )
    promo, discount = None, Decimal("0")
    if data.get("promo_code"):
        promo, discount = promo_services.validate(customer, data["promo_code"], quote.fare)
    try:
        with transaction.atomic():
            ride = Ride.objects.create(
                customer=customer,
                vehicle_type=quote.vehicle_type,
                pickup_address=data["pickup_address"],
                pickup_latitude=data["pickup_latitude"],
                pickup_longitude=data["pickup_longitude"],
                drop_address=data["drop_address"],
                drop_latitude=data["drop_latitude"],
                drop_longitude=data["drop_longitude"],
                estimated_distance_km=quote.distance_km,
                estimated_duration_minutes=quote.duration_minutes,
                estimated_fare=quote.fare,
                payment_method=data.get("payment_method", PaymentMethod.ONLINE),
                status=RideStatus.REQUESTED,
                idempotency_key=idempotency_key,
                start_pin=_new_start_pin(),
                promo_code=promo.code if promo else "",
                discount_amount=discount,
            )
            if promo is not None:
                promo_services.reserve(customer, promo, ride, discount)
            RideEvent.objects.create(ride=ride, from_status="", to_status=RideStatus.REQUESTED, actor=customer)
            transition(ride, RideStatus.SEARCHING, actor=customer)
    except IntegrityError:
        raise Conflict("You already have an active ride.", code="active_ride_exists")

    matching.advance(ride)
    ride.refresh_from_db()
    return ride


def get_customer_ride(customer, ride_id):
    """Fetch a customer's ride. Also moves a stalled search forward, so polling keeps dispatch alive."""
    ride = get_object_or_404(Ride, pk=ride_id, customer=customer)
    if ride.status == RideStatus.SEARCHING:
        matching.advance(ride)
        ride.refresh_from_db()
    return ride


def _free_captain(captain_id):
    """Put a captain back to ONLINE (or OFFLINE if no longer eligible) after leaving a ride."""
    captain = CaptainProfile.objects.select_for_update().get(pk=captain_id)
    captain.online_status = OnlineStatus.OFFLINE if eligibility_reasons(captain) else OnlineStatus.ONLINE
    captain.save(update_fields=["online_status", "updated_at"])
    return captain


def cancel_ride(ride, actor=None, reason="CANCELLED_BY_CUSTOMER", cancelled_by=None, note="", fee=Decimal("0")):
    """Cancel from any pre-start state. Frees the captain, releases any surrender or promo, records any fee,
    and notifies the other side."""
    if cancelled_by is None:
        cancelled_by = CancelledBy.SYSTEM if actor is None else CancelledBy.CUSTOMER
    with transaction.atomic():
        ride = Ride.objects.select_for_update().get(pk=ride.pk)
        if ride.status not in CANCELLABLE:
            raise Conflict("This ride can no longer be cancelled.", code="not_cancellable")
        engaged = ride.status in IN_PROGRESS_STATUSES
        transition(ride, RideStatus.CANCELLED, actor=actor, note=reason)
        ride.cancellation_reason = reason
        ride.cancelled_by = cancelled_by
        ride.cancellation_note = (note or "")[:300]
        ride.cancellation_fee = fee
        ride.cancellation_fee_status = FeeStatus.UNPAID if fee > 0 else FeeStatus.NONE
        ride.save(update_fields=[
            "cancellation_reason", "cancelled_by", "cancellation_note", "cancellation_fee",
            "cancellation_fee_status", "updated_at",
        ])
        RideOffer.objects.filter(ride=ride, status=OfferStatus.PENDING).update(
            status=OfferStatus.CANCELLED, responded_at=timezone.now()
        )
        subscription_services.release_surrender(ride)
        promo_services.release(ride)

        data = {"ride_id": str(ride.id)}
        if ride.captain_id:
            captain = _free_captain(ride.captain_id) if engaged else ride.captain
            if cancelled_by != CancelledBy.CAPTAIN:
                notify(captain.user, "RIDE_CANCELLED", "Ride cancelled", f"Reason: {reason}", data)
        message = f"Your ride was cancelled. A fee of ₹{fee} applies." if fee > 0 else "Your ride was cancelled."
        notify(ride.customer, "RIDE_CANCELLED", "Ride cancelled", message, data)
    return ride


def customer_cancel_fee(ride, reason, now=None):
    """The fee for a rider cancelling now: only after a captain accepted, past the free window,
    and never when the captain caused it or for safety."""
    config = PlatformConfig.load()
    if config.customer_cancel_fee <= 0 or ride.accepted_at is None:
        return Decimal("0")
    if ride.status not in IN_PROGRESS_STATUSES:
        return Decimal("0")
    if reason in (CustomerCancelReason.CAPTAIN_ASKED, CustomerCancelReason.SAFETY):
        return Decimal("0")
    now = now or timezone.now()
    if now - ride.accepted_at <= timedelta(seconds=config.cancel_free_window_seconds):
        return Decimal("0")
    return config.customer_cancel_fee


def customer_cancel(customer, ride_id, reason=CustomerCancelReason.OTHER, note=""):
    ride = get_object_or_404(Ride, pk=ride_id, customer=customer)
    fee = customer_cancel_fee(ride, reason)
    return cancel_ride(ride, actor=customer, reason=reason, cancelled_by=CancelledBy.CUSTOMER, note=note, fee=fee)


def cancel_preview(customer, ride_id):
    """What cancelling right now would cost, so the app can warn before the rider confirms."""
    ride = get_object_or_404(Ride, pk=ride_id, customer=customer)
    config = PlatformConfig.load()
    fee = customer_cancel_fee(ride, CustomerCancelReason.OTHER)
    free_until = None
    if ride.accepted_at and config.customer_cancel_fee > 0 and ride.status in IN_PROGRESS_STATUSES:
        free_until = ride.accepted_at + timedelta(seconds=config.cancel_free_window_seconds)
    return {
        "can_cancel": ride.status in CANCELLABLE,
        "fee": str(fee),
        "free_until": free_until,
        "reasons": [{"code": value, "label": label} for value, label in CustomerCancelReason.choices],
    }


def request_online_payment(customer, ride_id):
    ride = get_object_or_404(Ride, pk=ride_id, customer=customer)
    if ride.status != RideStatus.COMPLETED:
        raise Conflict("You can pay once the ride is completed.", code="not_completed")
    if ride.payment_method != PaymentMethod.ONLINE:
        raise Conflict("This ride is paid in cash to the captain.", code="cash_ride")
    if ride.payment_status == RidePaymentStatus.PAID:
        raise Conflict("This ride is already paid.", code="already_paid")

    pending = Payment.objects.filter(
        user=customer,
        payment_type=PaymentType.RIDE_PAYMENT,
        status=PaymentStatus.PENDING,
        metadata__ride_id=str(ride.id),
    ).first()
    if pending is not None:
        return pending
    return create_payment(customer, PaymentType.RIDE_PAYMENT, ride.payable_fare, {"ride_id": str(ride.id)})


def request_fee_payment(customer, ride_id):
    """Pay the cancellation or no-show fee of a cancelled ride online."""
    ride = get_object_or_404(Ride, pk=ride_id, customer=customer)
    if ride.cancellation_fee_status != FeeStatus.UNPAID:
        raise Conflict("There is no fee to pay for this ride.", code="no_fee_due")
    pending = Payment.objects.filter(
        user=customer,
        payment_type=PaymentType.CANCELLATION_FEE,
        status=PaymentStatus.PENDING,
        metadata__ride_id=str(ride.id),
    ).first()
    if pending is not None:
        return pending
    return create_payment(customer, PaymentType.CANCELLATION_FEE, ride.cancellation_fee, {"ride_id": str(ride.id)})


def on_fee_paid(payment):
    """Webhook handler. The fee compensates the captain who was cancelled on, through their wallet."""
    ride = Ride.objects.select_for_update().get(pk=payment.metadata["ride_id"])
    if ride.cancellation_fee_status != FeeStatus.UNPAID:
        return
    ride.cancellation_fee_status = FeeStatus.PAID
    ride.save(update_fields=["cancellation_fee_status", "updated_at"])
    if ride.captain_id:
        from apps.wallets import services as wallet_services
        from apps.wallets.models import WalletTxnKind

        wallet_services.credit(ride.captain, payment.amount, WalletTxnKind.CANCELLATION_FEE, f"ride:{ride.id}")


def waive_fee(ride, actor=None):
    with transaction.atomic():
        ride = Ride.objects.select_for_update().get(pk=ride.pk)
        if ride.cancellation_fee_status != FeeStatus.UNPAID:
            raise Conflict("This ride has no unpaid fee.", code="no_fee_due")
        ride.cancellation_fee_status = FeeStatus.WAIVED
        ride.save(update_fields=["cancellation_fee_status", "updated_at"])
    notify(ride.customer, "FEE_WAIVED", "Fee waived", "We have waived the fee for your cancelled ride.",
           {"ride_id": str(ride.id)})
    return ride


def on_ride_paid(payment):
    """Payment webhook handler. Marks the ride paid and settles its platform due if it was the platform ride."""
    ride = Ride.objects.select_for_update().get(pk=payment.metadata["ride_id"])
    if ride.payment_status == RidePaymentStatus.PAID:
        return
    ride.payment_status = RidePaymentStatus.PAID
    ride.save(update_fields=["payment_status", "updated_at"])
    if ride.is_platform_ride:
        PlatformDue.objects.filter(ride=ride, status=DueStatus.PENDING).update(
            status=DueStatus.SETTLED, settled_at=timezone.now(), payment=payment
        )
    notify(ride.customer, "PAYMENT_SUCCESS", "Payment successful", "Thanks for riding with us.", {"ride_id": str(ride.id)})


def tracking(customer, ride_id):
    ride = get_customer_ride(customer, ride_id)
    data = {
        "ride_id": str(ride.id),
        "status": ride.status,
        "pickup": {"address": ride.pickup_address, "latitude": ride.pickup_latitude, "longitude": ride.pickup_longitude},
        "drop": {"address": ride.drop_address, "latitude": ride.drop_latitude, "longitude": ride.drop_longitude},
        "captain": None,
        "start_pin": ride.start_pin if ride.status in PIN_VISIBLE_STATUSES else None,
    }
    if ride.captain_id and ride.status in IN_PROGRESS_STATUSES:
        captain = ride.captain
        vehicle = captain.vehicles.filter(vehicle_type=ride.vehicle_type, is_verified=True).first()
        data["captain"] = {
            "name": captain.user.first_name or "Your captain",
            "rating": captain.rating,
            "latitude": captain.current_latitude,
            "longitude": captain.current_longitude,
            "last_location_at": captain.last_location_at,
            "vehicle": (
                {
                    "type": vehicle.vehicle_type,
                    "registration_number": vehicle.registration_number,
                    "make": vehicle.make,
                    "model": vehicle.model,
                    "color": vehicle.color,
                }
                if vehicle
                else None
            ),
        }
    return data


def rate_ride(customer, ride_id, rating, comment=""):
    ride = get_object_or_404(Ride, pk=ride_id, customer=customer)
    if ride.status != RideStatus.COMPLETED:
        raise Conflict("You can rate a ride after it is completed.", code="not_completed")
    try:
        with transaction.atomic():
            Rating.objects.create(
                ride=ride, customer=customer, captain=ride.captain, rating=rating, comment=comment
            )
    except IntegrityError:
        raise Conflict("You have already rated this ride.", code="already_rated")

    captain = ride.captain
    average = Rating.objects.filter(captain=captain).aggregate(avg=Avg("rating"))["avg"] or 0
    captain.rating = Decimal(str(average)).quantize(Decimal("0.01"), ROUND_HALF_UP)
    captain.save(update_fields=["rating", "updated_at"])
    return Rating.objects.get(ride=ride)


# ---------- trip sharing ----------

def share_trip(customer, ride_id):
    """Create (or reuse) the public link for an active ride."""
    ride = get_object_or_404(Ride, pk=ride_id, customer=customer)
    if ride.status not in ACTIVE_STATUSES:
        raise Conflict("Only an active ride can be shared.", code="ride_not_active")
    link = RideShareLink.objects.filter(ride=ride, revoked_at__isnull=True).first()
    if link is None:
        link = RideShareLink.objects.create(ride=ride, token=secrets.token_urlsafe(32))
    return link


def stop_sharing(customer, ride_id):
    ride = get_object_or_404(Ride, pk=ride_id, customer=customer)
    RideShareLink.objects.filter(ride=ride, revoked_at__isnull=True).update(revoked_at=timezone.now())


def shared_trip(token):
    """What a family member sees. No phone numbers and no PIN; captain location only while the ride is live."""
    link = (
        RideShareLink.objects.select_related("ride__captain__user", "ride__customer")
        .filter(token=token, revoked_at__isnull=True)
        .first()
    )
    if link is None:
        raise Http404
    ride = link.ride
    ended_at = ride.completed_at or ride.cancelled_at
    if ended_at and timezone.now() > ended_at + timedelta(minutes=PlatformConfig.load().share_link_grace_minutes):
        raise Http404
    data = {
        "status": ride.status,
        "rider_name": ride.customer.first_name or "Rider",
        "vehicle_type": ride.vehicle_type,
        "pickup": {"address": ride.pickup_address, "latitude": ride.pickup_latitude, "longitude": ride.pickup_longitude},
        "drop": {"address": ride.drop_address, "latitude": ride.drop_latitude, "longitude": ride.drop_longitude},
        "started_at": ride.started_at,
        "completed_at": ride.completed_at,
        "captain": None,
    }
    if ride.captain_id and ride.status in IN_PROGRESS_STATUSES:
        captain = ride.captain
        vehicle = captain.vehicles.filter(vehicle_type=ride.vehicle_type, is_verified=True).first()
        data["captain"] = {
            "name": captain.user.first_name or "Captain",
            "latitude": captain.current_latitude,
            "longitude": captain.current_longitude,
            "last_location_at": captain.last_location_at,
            "registration_number": vehicle.registration_number if vehicle else "",
        }
    return data


# ---------- captain side ----------

def captain_offers(captain):
    return (
        RideOffer.objects.filter(captain=captain, status=OfferStatus.PENDING, expires_at__gt=timezone.now())
        .select_related("ride")
        .order_by("expires_at")
    )


def _offer_for_update(captain, ride_id):
    return (
        RideOffer.objects.select_for_update()
        .select_related("ride")
        .filter(captain=captain, ride_id=ride_id, status=OfferStatus.PENDING)
        .first()
    )


def accept_offer(captain, ride_id):
    expired = False
    with transaction.atomic():
        # Reload the captain under lock: the caller's copy may be stale, and BUSY must be decided on current data.
        captain = CaptainProfile.objects.select_for_update().get(pk=captain.pk)
        offer = _offer_for_update(captain, ride_id)
        if offer is None:
            raise Conflict("You have no open request for this ride.", code="no_offer")
        ride = Ride.objects.select_for_update().get(pk=offer.ride_id)
        now = timezone.now()

        if offer.expires_at <= now:
            offer.status = OfferStatus.EXPIRED
            offer.responded_at = now
            offer.save(update_fields=["status", "responded_at", "updated_at"])
            expired = True
        else:
            if captain.online_status != OnlineStatus.ONLINE:
                raise Conflict("Go online to accept rides.", code="captain_offline")
            if ride.status != RideStatus.SEARCHING:
                raise Conflict("This ride is no longer available.", code="ride_unavailable")
            reasons = eligibility_reasons(captain, ride.vehicle_type)
            if reasons:
                raise Forbidden(describe_reasons(reasons), code=reasons[0])

            transition(ride, RideStatus.ACCEPTED, actor=captain.user)
            ride.captain = captain
            ride.save(update_fields=["captain", "updated_at"])
            offer.status = OfferStatus.ACCEPTED
            offer.responded_at = now
            offer.save(update_fields=["status", "responded_at", "updated_at"])
            captain.online_status = OnlineStatus.BUSY
            captain.save(update_fields=["online_status", "updated_at"])
            notify(ride.customer, "RIDE_ACCEPTED", "Captain accepted", "Your captain is on the way.", {"ride_id": str(ride.id)})

    if expired:
        matching.advance(ride)
        raise Conflict("This request has expired.", code="offer_expired")
    return ride


def reject_offer(captain, ride_id):
    with transaction.atomic():
        offer = _offer_for_update(captain, ride_id)
        if offer is None:
            raise Conflict("You have no open request for this ride.", code="no_offer")
        offer.status = OfferStatus.REJECTED
        offer.responded_at = timezone.now()
        offer.save(update_fields=["status", "responded_at", "updated_at"])
        ride = offer.ride
    matching.advance(ride)
    return ride


def _captain_ride(captain, ride_id, lock=True):
    queryset = Ride.objects.select_for_update() if lock else Ride.objects
    ride = queryset.filter(pk=ride_id).first()
    if ride is None:
        raise Http404
    if ride.captain_id != captain.id:
        raise Forbidden("This ride is not yours.", code="not_your_ride")
    return ride


def mark_arrived(captain, ride_id):
    with transaction.atomic():
        ride = _captain_ride(captain, ride_id)
        transition(ride, RideStatus.CAPTAIN_ARRIVED, actor=captain.user)
    notify(ride.customer, "CAPTAIN_ARRIVED", "Captain arrived", "Your captain is at the pickup point.", {"ride_id": str(ride.id)})
    return ride


def start_ride(captain, ride_id, pin=None):
    """Start the trip. When PINs are on, the captain must enter the rider's PIN, so the right
    rider is in the right vehicle. Wrong guesses are limited per ride."""
    config = PlatformConfig.load()
    wrong_pin = False
    with transaction.atomic():
        ride = _captain_ride(captain, ride_id)
        needs_pin = config.require_start_pin and ride.start_pin and ride.status == RideStatus.CAPTAIN_ARRIVED
        if needs_pin and ride.start_pin_attempts >= config.start_pin_max_attempts:
            raise RateLimited(
                "Too many wrong PINs. Ask the rider to check the PIN in their app or contact support.",
                code="pin_locked",
            )
        if needs_pin and not secrets.compare_digest(str(pin or ""), ride.start_pin):
            if pin:
                ride.start_pin_attempts += 1
                ride.save(update_fields=["start_pin_attempts", "updated_at"])
            wrong_pin = True
        else:
            transition(ride, RideStatus.STARTED, actor=captain.user)
    if wrong_pin:
        if not pin:
            raise DomainError("Enter the rider's 4-digit PIN to start the ride.", code="pin_required")
        raise DomainError("That PIN is not correct. Ask the rider for the PIN in their app.", code="wrong_pin")
    notify(ride.customer, "RIDE_STARTED", "Ride started", "Enjoy your trip.", {"ride_id": str(ride.id)})
    return ride


def captain_cancel(captain, ride_id, reason, note=""):
    """Captain drops an accepted ride.

    - Rider no-show (after waiting at pickup) or rider asked: the ride is cancelled; a no-show fee may apply.
    - Anything else: the ride goes back to searching and is offered to the next captain,
      so the rider is not stranded. It counts against the captain's cancellation record.
    """
    config = PlatformConfig.load()
    redispatch = reason not in (CaptainCancelReason.CUSTOMER_NOT_AT_PICKUP, CaptainCancelReason.CUSTOMER_ASKED)
    with transaction.atomic():
        ride = _captain_ride(captain, ride_id)
        if ride.status not in (RideStatus.ACCEPTED, RideStatus.CAPTAIN_ARRIVED):
            raise Conflict("This ride can no longer be cancelled.", code="not_cancellable")
        if reason == CaptainCancelReason.CUSTOMER_NOT_AT_PICKUP:
            if ride.status != RideStatus.CAPTAIN_ARRIVED:
                raise Conflict("Mark yourself arrived at pickup first.", code="not_arrived")
            if timezone.now() < ride.arrived_at + timedelta(minutes=config.no_show_wait_minutes):
                raise Conflict(
                    f"Please wait {config.no_show_wait_minutes} minutes at pickup before cancelling.",
                    code="no_show_wait",
                )
        if redispatch:
            transition(ride, RideStatus.SEARCHING, actor=captain.user, note=f"captain_cancelled:{reason}")
            ride.captain = None
            ride.accepted_at = None
            ride.arrived_at = None
            ride.start_pin_attempts = 0
            ride.save(update_fields=["captain", "accepted_at", "arrived_at", "start_pin_attempts", "updated_at"])
            subscription_services.release_surrender(ride)
            profile = _free_captain(captain.pk)
            profile.cancelled_rides += 1
            profile.save(update_fields=["cancelled_rides", "updated_at"])

    if redispatch:
        notify(ride.customer, "CAPTAIN_CANCELLED", "Finding you another captain",
               "Your captain had to cancel. We are matching you with someone nearby.", {"ride_id": str(ride.id)})
        matching.advance(ride)
        ride.refresh_from_db()
        return ride

    fee = config.customer_no_show_fee if reason == CaptainCancelReason.CUSTOMER_NOT_AT_PICKUP else Decimal("0")
    return cancel_ride(ride, actor=captain.user, reason=reason, cancelled_by=CancelledBy.CAPTAIN, note=note, fee=fee)


def complete_ride(captain, ride_id):
    """Finish a ride. The fare is the one locked at request time, so the client cannot change it."""
    with transaction.atomic():
        ride = _captain_ride(captain, ride_id)
        transition(ride, RideStatus.COMPLETED, actor=captain.user)
        ride.final_fare = ride.estimated_fare
        ride.save(update_fields=["final_fare", "updated_at"])

        subscription_services.record_completed_ride(ride)
        ride.save(update_fields=["is_platform_ride", "share_reason", "platform_share_amount", "updated_at"])

        captain = CaptainProfile.objects.select_for_update().get(pk=captain.pk)
        captain.total_rides += 1
        captain.online_status = OnlineStatus.OFFLINE if eligibility_reasons(captain) else OnlineStatus.ONLINE
        captain.save(update_fields=["total_rides", "online_status", "updated_at"])
        promo_services.on_ride_completed(ride)

    notify(ride.customer, "RIDE_COMPLETED", "Ride completed", f"Fare: ₹{ride.payable_fare}", {"ride_id": str(ride.id)})
    notify(captain.user, "RIDE_COMPLETED", "Ride completed", f"Fare: ₹{ride.final_fare}", {"ride_id": str(ride.id)})
    return ride


def collect_cash(captain, ride_id):
    with transaction.atomic():
        ride = _captain_ride(captain, ride_id)
        if ride.status != RideStatus.COMPLETED:
            raise Conflict("Collect cash after the ride is completed.", code="not_completed")
        if ride.payment_method != PaymentMethod.CASH:
            raise Conflict("This ride is paid online.", code="online_ride")
        if ride.payment_status == RidePaymentStatus.PAID:
            raise Conflict("Cash for this ride is already recorded.", code="already_paid")
        ride.payment_status = RidePaymentStatus.PAID
        ride.save(update_fields=["payment_status", "updated_at"])
    return ride


def surrender(captain, ride_id):
    ride = _captain_ride(captain, ride_id, lock=False)
    subscription_services.surrender_ride(captain, ride)
    return ride


def record_captain_location(captain, data):
    """Update the captain's live position, and keep a sample if they are on a ride."""
    update_location(
        captain,
        data["latitude"],
        data["longitude"],
        heading=data.get("heading"),
        speed=data.get("speed"),
    )
    ride = Ride.objects.filter(captain=captain, status__in=IN_PROGRESS_STATUSES).first()
    if ride is not None:
        RideLocation.objects.create(
            ride=ride,
            captain=captain,
            latitude=data["latitude"],
            longitude=data["longitude"],
            heading=data.get("heading"),
            speed=data.get("speed"),
        )


def earnings_summary(captain):
    completed = Ride.objects.filter(captain=captain, status=RideStatus.COMPLETED)
    totals = completed.aggregate(fares=Sum("final_fare"), platform=Sum("platform_share_amount"))
    fares = totals["fares"] or Decimal("0")
    platform = totals["platform"] or Decimal("0")

    day_start = service_day_start(timezone.now())
    today = completed.filter(completed_at__gte=day_start)
    today_totals = today.aggregate(fares=Sum("final_fare"), platform=Sum("platform_share_amount"))
    today_fares = today_totals["fares"] or Decimal("0")
    today_platform = today_totals["platform"] or Decimal("0")

    pending = subscription_services.pending_dues_total(captain)
    return {
        "completed_rides": completed.count(),
        "fare_total": str(fares),
        "platform_share": str(platform),
        "net_earnings": str(fares - platform),
        "today": {
            "completed_rides": today.count(),
            "net_earnings": str(today_fares - today_platform),
        },
        "pending_dues": str(pending),
    }


# ---------- background sweep ----------

def sweep_searching_rides():
    """Advance every ride still searching. Called from run_periodic_jobs."""
    count = 0
    for ride in Ride.objects.filter(status=RideStatus.SEARCHING):
        matching.advance(ride)
        count += 1
    return count
