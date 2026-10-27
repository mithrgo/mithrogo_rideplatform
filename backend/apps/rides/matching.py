from datetime import timedelta

from django.utils import timezone

from core.geo import haversine_km
from core.models import PlatformConfig
from apps.captains.models import CaptainProfile, KycStatus, OnlineStatus
from apps.captains.services import eligibility_reasons
from apps.notifications.services import notify
from apps.rides.models import OfferStatus, RideOffer, RideStatus


def eligible_candidates(ride):
    """Captains who may be offered this ride, nearest first.

    Filters in one query where possible: approved, active, ONLINE (not BUSY), fresh location,
    verified vehicle of the requested type, not already offered this ride, not holding an offer elsewhere.
    Then radius and the plan/eligibility rules, which are the same ones go-online uses.
    """
    config = PlatformConfig.load()
    fresh_since = timezone.now() - timedelta(seconds=config.location_freshness_seconds)
    offered_before = RideOffer.objects.filter(ride=ride).values("captain_id")
    holding_offer = RideOffer.objects.filter(status=OfferStatus.PENDING).values("captain_id")

    queryset = (
        CaptainProfile.objects.select_related("user")
        .filter(
            online_status=OnlineStatus.ONLINE,
            kyc_status=KycStatus.APPROVED,
            user__is_active=True,
            current_latitude__isnull=False,
            last_location_at__gte=fresh_since,
            vehicles__vehicle_type=ride.vehicle_type,
            vehicles__is_verified=True,
        )
        .exclude(pk__in=offered_before)
        .exclude(pk__in=holding_offer)
        .distinct()
    )

    found = []
    radius = float(config.search_radius_km)
    for captain in queryset:
        distance = haversine_km(captain.current_latitude, captain.current_longitude, ride.pickup_latitude, ride.pickup_longitude)
        if distance > radius:
            continue
        if eligibility_reasons(captain, ride.vehicle_type):
            continue
        found.append((distance, captain))
    found.sort(key=lambda item: item[0])
    return found


def offer_next(ride):
    """Offer the ride to the nearest eligible captain. One pending offer per ride at a time."""
    config = PlatformConfig.load()
    if RideOffer.objects.filter(ride=ride, status=OfferStatus.PENDING).exists():
        return None
    attempts = RideOffer.objects.filter(ride=ride).count()
    if attempts >= config.max_offer_attempts:
        return None
    candidates = eligible_candidates(ride)
    if not candidates:
        return None

    distance, captain = candidates[0]
    now = timezone.now()
    offer = RideOffer.objects.create(
        ride=ride,
        captain=captain,
        sequence=attempts + 1,
        distance_km=round(distance, 2),
        status=OfferStatus.PENDING,
        expires_at=now + timedelta(seconds=config.offer_timeout_seconds),
    )
    notify(
        captain.user,
        "NEW_RIDE_REQUEST",
        "New ride request",
        f"Pickup: {ride.pickup_address}",
        {"ride_id": str(ride.id)},
    )
    return offer


def advance(ride):
    """Expire timed-out offers, then offer to the next captain. Cancels the ride when nobody is left."""
    from apps.rides import services

    now = timezone.now()
    RideOffer.objects.filter(ride=ride, status=OfferStatus.PENDING, expires_at__lte=now).update(
        status=OfferStatus.EXPIRED, responded_at=now
    )
    ride.refresh_from_db()
    if ride.status != RideStatus.SEARCHING:
        return
    offer_next(ride)
    if RideOffer.objects.filter(ride=ride, status=OfferStatus.PENDING).exists():
        return
    config = PlatformConfig.load()
    exhausted = RideOffer.objects.filter(ride=ride).count() >= config.max_offer_attempts
    searched_for = (now - ride.created_at).total_seconds()
    # With nobody eligible right now, keep searching (each poll retries) until the search window closes.
    if exhausted or searched_for >= config.search_timeout_seconds:
        services.cancel_ride(ride, actor=None, reason="NO_CAPTAIN_AVAILABLE")
