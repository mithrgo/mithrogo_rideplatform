from decimal import Decimal
from itertools import count

from django.utils import timezone

from apps.captains import services as captain_services
from apps.captains.models import KycStatus
from apps.captains.services import ensure_profile, update_location
from apps.customers.services import ensure_profile as ensure_customer_profile
from apps.payments import services as payment_services
from apps.subscriptions import services as subscription_services
from apps.users.models import Role, User
from apps.vehicles.models import Vehicle, VehicleType

PICKUP = (Decimal("18.672500"), Decimal("78.094000"))
DROP = (Decimal("18.700000"), Decimal("78.120000"))
NEAR_PICKUP = (Decimal("18.674000"), Decimal("78.095000"))  # roughly 250 m from pickup

_sequence = count(9800000000)


def new_phone():
    return f"+91{next(_sequence)}"


def make_user(role, phone=None, **extra):
    user = User.objects.create_user(phone=phone or new_phone(), role=role, is_verified=True, **extra)
    if role == Role.CUSTOMER:
        ensure_customer_profile(user)
    return user


def make_captain(
    *,
    plan="daily",
    vehicle_type=VehicleType.BIKE,
    approved=True,
    verified=True,
    location=NEAR_PICKUP,
    online=True,
):
    """A captain who is fully set up: approved KYC, verified vehicle, active plan, location, and online."""
    user = make_user(Role.CAPTAIN, first_name="Ravi")
    profile = ensure_profile(user)
    if approved:
        profile.kyc_status = KycStatus.APPROVED
        profile.save(update_fields=["kyc_status", "updated_at"])
    Vehicle.objects.create(
        captain=profile,
        vehicle_type=vehicle_type,
        registration_number=f"TS{next(_sequence)}",
        make="Bajaj",
        model="RE",
        color="Yellow",
        is_verified=verified,
        verified_at=timezone.now() if verified else None,
    )
    if verified:
        captain_services.select_vehicle_for_today(profile, vehicle_type)
    if plan == "daily":
        sub, payment = subscription_services.create_daily_subscription_payment(profile, f"DAILY_{vehicle_type}")
        payment_services.mark_success(payment.provider_order_id, f"pay_{payment.id.hex[:12]}", payment.amount)
    elif plan == "ride_share":
        subscription_services.switch_to_ride_share(profile, f"RIDE_SHARE_{vehicle_type}")
    if location is not None:
        update_location(profile, location[0], location[1])
    if online:
        captain_services.go_online(profile)
    return profile


def ride_data(vehicle_type=VehicleType.BIKE, payment_method="ONLINE", pickup=PICKUP, drop=DROP):
    """Ride request as the service layer receives it (Decimal coordinates)."""
    return {
        "vehicle_type": vehicle_type,
        "pickup_address": "Pickup point",
        "pickup_latitude": pickup[0],
        "pickup_longitude": pickup[1],
        "drop_address": "Drop point",
        "drop_latitude": drop[0],
        "drop_longitude": drop[1],
        "device_latitude": pickup[0],
        "device_longitude": pickup[1],
        "payment_method": payment_method,
    }


def ride_payload(vehicle_type=VehicleType.BIKE, payment_method="ONLINE", pickup=PICKUP, drop=DROP):
    """Ride request as the mobile apps send it (strings)."""
    payload = ride_data(vehicle_type, payment_method, pickup, drop)
    for key in ("pickup_latitude", "pickup_longitude", "drop_latitude", "drop_longitude", "device_latitude", "device_longitude"):
        payload[key] = str(payload[key])
    return payload


def send_webhook(api, event):
    """POST a gateway event the way the real gateway does: JSON body plus HMAC signature header."""
    import json

    from apps.payments.providers import MockPaymentProvider

    body = json.dumps(event).encode()
    signature = MockPaymentProvider.sign(body)
    return api.post(
        "/api/v1/payments/webhook/",
        data=body,
        content_type="application/json",
        HTTP_X_PAYMENT_SIGNATURE=signature,
    )


def captured_event(payment):
    return {
        "event": "payment.captured",
        "provider_order_id": payment.provider_order_id,
        "provider_payment_id": f"pay_{payment.id.hex[:12]}",
        "amount": str(payment.amount),
    }


class CapturingSmsProvider:
    """Test SMS sender: records each OTP so tests can read the code the user would receive."""

    sent = []
    fail = False

    def send_otp(self, phone, code, ttl_minutes):
        if CapturingSmsProvider.fail:
            raise RuntimeError("gateway down")
        CapturingSmsProvider.sent.append((phone, code))


def last_code_sent_to(phone):
    for sent_phone, code in reversed(CapturingSmsProvider.sent):
        if sent_phone == phone:
            return code
    raise AssertionError(f"no SMS was sent to {phone}")
