from decimal import Decimal

import pytest

from apps.rides import services
from core.exceptions import DomainError
from core.models import PlatformConfig, ServiceZone
from tests.helpers import ride_data

MUMBAI = (Decimal("19.076000"), Decimal("72.877700"))


@pytest.mark.django_db
def test_booking_inside_service_area_works(customer):
    assert services.create_ride(customer, ride_data()).pk


@pytest.mark.django_db
@pytest.mark.parametrize(
    "overrides, code",
    [
        ({"pickup_latitude": MUMBAI[0], "pickup_longitude": MUMBAI[1]}, "pickup_outside_service_area"),
        ({"drop_latitude": MUMBAI[0], "drop_longitude": MUMBAI[1]}, "drop_outside_service_area"),
        ({"device_latitude": MUMBAI[0], "device_longitude": MUMBAI[1]}, "booker_outside_service_area"),
    ],
)
def test_booking_outside_service_area_is_rejected(customer, overrides, code):
    data = {**ride_data(), **overrides}
    with pytest.raises(DomainError) as error:
        services.create_ride(customer, data)
    assert error.value.code == code


@pytest.mark.django_db
def test_booking_needs_the_riders_device_location(customer):
    data = ride_data()
    del data["device_latitude"], data["device_longitude"]
    with pytest.raises(DomainError) as error:
        services.create_ride(customer, data)
    assert error.value.code == "device_location_required"


@pytest.mark.django_db
def test_estimate_rejects_a_drop_outside_the_area(customer):
    data = {**ride_data(), "drop_latitude": MUMBAI[0], "drop_longitude": MUMBAI[1]}
    with pytest.raises(DomainError):
        services.estimate(data, customer=customer)


@pytest.mark.django_db
def test_restriction_can_be_turned_off(customer):
    config = PlatformConfig.load()
    config.restrict_to_service_area = False
    config.save()
    data = {**ride_data(), "device_latitude": MUMBAI[0], "device_longitude": MUMBAI[1]}
    assert services.create_ride(customer, data).pk


SQUARE = "19.0, 72.8\n19.0, 72.9\n19.2, 72.9\n19.2, 72.8"


@pytest.mark.django_db
def test_extra_polygon_zone_allows_booking_there(customer):
    ServiceZone.objects.create(name="Mumbai pilot", shape="POLYGON", polygon_points=SQUARE)
    data = {**ride_data(), "pickup_latitude": MUMBAI[0], "pickup_longitude": MUMBAI[1],
            "drop_latitude": Decimal("19.1"), "drop_longitude": Decimal("72.85"),
            "device_latitude": MUMBAI[0], "device_longitude": MUMBAI[1]}
    assert services.create_ride(customer, data).pk


@pytest.mark.django_db
def test_inactive_zone_is_ignored(customer):
    ServiceZone.objects.create(name="Off", shape="CIRCLE", latitude=MUMBAI[0], longitude=MUMBAI[1],
                               radius_km=10, is_active=False)
    data = {**ride_data(), "drop_latitude": MUMBAI[0], "drop_longitude": MUMBAI[1]}
    with pytest.raises(DomainError):
        services.estimate(data, customer=customer)


@pytest.mark.django_db
def test_bad_polygon_is_rejected_by_validation():
    from django.core.exceptions import ValidationError

    with pytest.raises(ValidationError):
        ServiceZone(name="Bad", shape="POLYGON", polygon_points="1,2\nnot a point").full_clean()
