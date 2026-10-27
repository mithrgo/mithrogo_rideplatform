from datetime import timedelta
from decimal import Decimal

import pytest
from django.utils import timezone

from apps.captains import services as captain_services
from apps.captains.models import CaptainProfile, OnlineStatus
from apps.rides import services
from apps.rides.models import OfferStatus, Ride, RideOffer, RideStatus
from apps.users.models import Role
from apps.vehicles.models import VehicleType
from core.exceptions import Conflict
from core.models import PlatformConfig
from tests.helpers import NEAR_PICKUP, make_captain, make_user, ride_data

# About 1.5 km from pickup (inside the 3 km radius, but further than NEAR_PICKUP).
MIDDLE = (Decimal("18.684000"), Decimal("78.094000"))
# About 5 km from pickup (outside the radius).
FAR = (Decimal("18.717000"), Decimal("78.094000"))


def pending_offer(ride):
    return RideOffer.objects.filter(ride=ride, status=OfferStatus.PENDING).select_related("captain__user").first()


@pytest.mark.django_db
def test_nearest_eligible_captain_gets_the_offer():
    near = make_captain(location=NEAR_PICKUP)
    make_captain(location=MIDDLE)
    customer = make_user(Role.CUSTOMER)

    ride = services.create_ride(customer, ride_data())

    assert ride.status == RideStatus.SEARCHING
    assert pending_offer(ride).captain_id == near.id


@pytest.mark.django_db
def test_captain_outside_the_radius_is_not_offered_and_ride_is_cancelled():
    PlatformConfig.objects.update_or_create(pk=1, defaults={"search_timeout_seconds": 0})
    make_captain(location=FAR)
    customer = make_user(Role.CUSTOMER)

    ride = services.create_ride(customer, ride_data())

    assert ride.status == RideStatus.CANCELLED
    assert ride.cancellation_reason == "NO_CAPTAIN_AVAILABLE"


@pytest.mark.django_db
def test_captain_with_stale_location_is_not_matched():
    PlatformConfig.objects.update_or_create(pk=1, defaults={"search_timeout_seconds": 0})
    captain = make_captain(location=NEAR_PICKUP)
    CaptainProfile.objects.filter(pk=captain.pk).update(last_location_at=timezone.now() - timedelta(minutes=5))
    customer = make_user(Role.CUSTOMER)

    ride = services.create_ride(customer, ride_data())

    assert ride.status == RideStatus.CANCELLED
    assert not RideOffer.objects.filter(captain=captain).exists()


@pytest.mark.django_db
def test_busy_captain_is_not_offered():
    PlatformConfig.objects.update_or_create(pk=1, defaults={"search_timeout_seconds": 0})
    captain = make_captain(location=NEAR_PICKUP)
    CaptainProfile.objects.filter(pk=captain.pk).update(online_status=OnlineStatus.BUSY)
    customer = make_user(Role.CUSTOMER)

    ride = services.create_ride(customer, ride_data())

    assert ride.status == RideStatus.CANCELLED


@pytest.mark.django_db
def test_captain_without_the_requested_vehicle_type_is_not_offered():
    PlatformConfig.objects.update_or_create(pk=1, defaults={"search_timeout_seconds": 0})
    make_captain(location=NEAR_PICKUP, vehicle_type=VehicleType.AUTO)
    customer = make_user(Role.CUSTOMER)

    ride = services.create_ride(customer, ride_data(vehicle_type=VehicleType.BIKE))

    assert ride.status == RideStatus.CANCELLED


@pytest.mark.django_db
def test_rejection_moves_the_offer_to_the_next_captain():
    first = make_captain(location=NEAR_PICKUP)
    second = make_captain(location=MIDDLE)
    customer = make_user(Role.CUSTOMER)
    ride = services.create_ride(customer, ride_data())
    assert pending_offer(ride).captain_id == first.id

    services.reject_offer(first, ride.id)

    assert pending_offer(ride).captain_id == second.id
    assert RideOffer.objects.get(ride=ride, captain=first).status == OfferStatus.REJECTED


@pytest.mark.django_db
def test_timed_out_offer_moves_to_the_next_captain(clock):
    first = make_captain(location=NEAR_PICKUP)
    second = make_captain(location=MIDDLE)
    customer = make_user(Role.CUSTOMER)
    ride = services.create_ride(customer, ride_data())

    clock.advance(seconds=PlatformConfig.load().offer_timeout_seconds + 1)
    services.get_customer_ride(customer, ride.id)

    assert RideOffer.objects.get(ride=ride, captain=first).status == OfferStatus.EXPIRED
    assert pending_offer(ride).captain_id == second.id


@pytest.mark.django_db
def test_ride_is_cancelled_after_max_offer_attempts():
    PlatformConfig.objects.update_or_create(pk=1, defaults={"max_offer_attempts": 2})
    first = make_captain(location=NEAR_PICKUP)
    second = make_captain(location=MIDDLE)
    customer = make_user(Role.CUSTOMER)
    ride = services.create_ride(customer, ride_data())

    services.reject_offer(first, ride.id)
    services.reject_offer(second, ride.id)
    ride.refresh_from_db()

    assert ride.status == RideStatus.CANCELLED
    assert ride.cancellation_reason == "NO_CAPTAIN_AVAILABLE"


@pytest.mark.django_db
def test_only_one_captain_can_accept_a_ride():
    first = make_captain(location=NEAR_PICKUP)
    second = make_captain(location=MIDDLE)
    customer = make_user(Role.CUSTOMER)
    ride = services.create_ride(customer, ride_data())

    services.accept_offer(first, ride.id)

    with pytest.raises(Conflict) as info:
        services.accept_offer(second, ride.id)
    assert info.value.code == "no_offer"
    ride.refresh_from_db()
    assert ride.captain_id == first.id
    assert ride.status == RideStatus.ACCEPTED


@pytest.mark.django_db
def test_expired_offer_cannot_be_accepted_and_moves_on(clock):
    first = make_captain(location=NEAR_PICKUP)
    second = make_captain(location=MIDDLE)
    customer = make_user(Role.CUSTOMER)
    ride = services.create_ride(customer, ride_data())

    clock.advance(seconds=PlatformConfig.load().offer_timeout_seconds + 1)
    with pytest.raises(Conflict) as info:
        services.accept_offer(first, ride.id)

    assert info.value.code == "offer_expired"
    assert pending_offer(ride).captain_id == second.id


@pytest.mark.django_db
def test_offline_captain_cannot_accept_even_with_an_open_offer():
    captain = make_captain(location=NEAR_PICKUP)
    customer = make_user(Role.CUSTOMER)
    ride = services.create_ride(customer, ride_data())
    CaptainProfile.objects.filter(pk=captain.pk).update(online_status=OnlineStatus.OFFLINE)

    with pytest.raises(Conflict) as info:
        services.accept_offer(captain, ride.id)

    assert info.value.code == "captain_offline"


@pytest.mark.django_db
def test_customer_with_an_active_ride_cannot_request_another():
    make_captain(location=NEAR_PICKUP)
    customer = make_user(Role.CUSTOMER)
    services.create_ride(customer, ride_data())

    with pytest.raises(Conflict) as info:
        services.create_ride(customer, ride_data())

    assert info.value.code == "active_ride_exists"


@pytest.mark.django_db
def test_same_idempotency_key_returns_the_same_ride():
    make_captain(location=NEAR_PICKUP)
    customer = make_user(Role.CUSTOMER)

    first = services.create_ride(customer, ride_data(), idempotency_key="abc-123")
    again = services.create_ride(customer, ride_data(), idempotency_key="abc-123")

    assert first.id == again.id
    assert Ride.objects.filter(customer=customer).count() == 1


@pytest.mark.django_db
def test_going_offline_is_refused_while_on_a_ride():
    captain = make_captain(location=NEAR_PICKUP)
    customer = make_user(Role.CUSTOMER)
    ride = services.create_ride(customer, ride_data())
    services.accept_offer(captain, ride.id)

    with pytest.raises(Conflict) as info:
        captain_services.go_offline(captain)

    assert info.value.code == "captain_busy"


@pytest.mark.django_db
def test_ride_keeps_searching_until_the_search_window_closes():
    make_captain(location=FAR)
    customer = make_user(Role.CUSTOMER)

    ride = services.create_ride(customer, ride_data())

    assert ride.status == RideStatus.SEARCHING
