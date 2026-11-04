"""The captain's 30-second acceptance window is enforced by the backend, not by the app's countdown."""

from datetime import timedelta
from decimal import Decimal

import pytest
from django.utils import timezone

from apps.captains.models import CaptainProfile, OnlineStatus
from apps.rides import services
from apps.rides.models import OfferStatus, RideOffer, RideStatus
from apps.users.models import Role
from core.exceptions import Conflict
from core.models import PlatformConfig
from tests.helpers import NEAR_PICKUP, make_captain, make_user, ride_data

# Close to pickup, so both captains are eligible.
NEAR_TOO = (Decimal("18.673000"), Decimal("78.095000"))


def _offer_for(ride, captain):
    return RideOffer.objects.get(ride=ride, captain=captain)


@pytest.mark.django_db
def test_the_offer_window_is_30_seconds_by_default(clock):
    make_captain(location=NEAR_PICKUP)
    customer = make_user(Role.CUSTOMER)

    ride = services.create_ride(customer, ride_data())
    offer = RideOffer.objects.get(ride=ride, status=OfferStatus.PENDING)

    assert PlatformConfig.load().offer_timeout_seconds == 30
    assert offer.expires_at - timezone.now() == timedelta(seconds=30)


@pytest.mark.django_db
def test_a_captain_can_accept_within_the_window(clock):
    captain = make_captain(location=NEAR_PICKUP)
    customer = make_user(Role.CUSTOMER)
    ride = services.create_ride(customer, ride_data())

    clock.advance(seconds=29)
    accepted = services.accept_offer(captain, ride.id)

    assert accepted.status == RideStatus.ACCEPTED
    assert accepted.captain_id == captain.id


@pytest.mark.django_db
def test_an_accept_after_the_window_is_refused_and_the_offer_expires(clock):
    captain = make_captain(location=NEAR_PICKUP)
    customer = make_user(Role.CUSTOMER)
    ride = services.create_ride(customer, ride_data())

    clock.advance(seconds=31)
    with pytest.raises(Conflict) as refused:
        services.accept_offer(captain, ride.id)

    ride.refresh_from_db()
    assert refused.value.code == "offer_expired"
    assert _offer_for(ride, captain).status == OfferStatus.EXPIRED
    assert ride.status != RideStatus.ACCEPTED
    assert ride.captain_id is None


@pytest.mark.django_db
def test_a_delayed_accept_request_cannot_take_an_expired_offer(clock):
    captain = make_captain(location=NEAR_PICKUP)
    customer = make_user(Role.CUSTOMER)
    ride = services.create_ride(customer, ride_data())

    # The request was sent at 29 s but processed after the window closed.
    clock.advance(seconds=30)
    with pytest.raises(Conflict):
        services.accept_offer(captain, ride.id)

    ride.refresh_from_db()
    assert ride.captain_id is None
    assert CaptainProfile.objects.get(pk=captain.pk).online_status == OnlineStatus.ONLINE


@pytest.mark.django_db
def test_a_ride_already_taken_cannot_be_accepted_by_a_second_captain(clock):
    first = make_captain(location=NEAR_PICKUP)
    second = make_captain(location=NEAR_TOO)
    customer = make_user(Role.CUSTOMER)
    ride = services.create_ride(customer, ride_data())
    # create_ride offered the ride to one captain. Give the other a live offer too, as if it had been
    # sent the request at the same time. Both are now allowed to tap Accept.
    offered = RideOffer.objects.get(ride=ride).captain
    other = second if offered.pk == first.pk else first
    RideOffer.objects.create(
        ride=ride,
        captain=other,
        sequence=2,
        distance_km=Decimal("0.50"),
        status=OfferStatus.PENDING,
        expires_at=timezone.now() + timedelta(seconds=30),
    )

    services.accept_offer(other, ride.id)
    with pytest.raises(Conflict) as taken:
        services.accept_offer(offered, ride.id)

    ride.refresh_from_db()
    assert taken.value.code == "ride_unavailable"
    assert ride.captain_id == other.id


@pytest.mark.django_db
def test_the_same_offer_cannot_be_accepted_twice(clock):
    captain = make_captain(location=NEAR_PICKUP)
    customer = make_user(Role.CUSTOMER)
    ride = services.create_ride(customer, ride_data())
    services.accept_offer(captain, ride.id)

    with pytest.raises(Conflict) as again:
        services.accept_offer(captain, ride.id)

    assert again.value.code == "no_offer"
