import pytest
from rest_framework.test import APIClient

from core.models import AuditLog, QuickPlace
from apps.users.models import Role
from tests.helpers import make_user

pytestmark = pytest.mark.django_db

PLACE = {
    "name": "Railway Station",
    "address": "Nizamabad Junction, Telangana",
    "latitude": "18.678787",
    "longitude": "78.103517",
    "icon": "train",
    "sort_order": 1,
}


def client_for(user):
    api = APIClient()
    api.force_authenticate(user=user)
    return api


def test_customer_sees_only_active_places_in_admin_order():
    QuickPlace.objects.create(name="B", address="b", latitude=18.6, longitude=78.1, sort_order=2)
    QuickPlace.objects.create(name="A", address="a", latitude=18.6, longitude=78.1, sort_order=1)
    QuickPlace.objects.create(name="Hidden", address="h", latitude=18.6, longitude=78.1, is_active=False)

    response = client_for(make_user(Role.CUSTOMER)).get("/api/v1/customers/quick-places/")

    assert response.status_code == 200
    assert [p["name"] for p in response.json()] == ["A", "B"]


def test_admin_can_create_edit_and_delete_a_place_and_it_is_audited():
    admin = client_for(make_user(Role.ADMIN))

    created = admin.post("/api/v1/admin/quick-places/", PLACE, format="json")
    assert created.status_code == 201
    place_id = created.json()["id"]

    assert admin.patch(f"/api/v1/admin/quick-places/{place_id}/", {"name": "Station"}, format="json").status_code == 200
    assert QuickPlace.objects.get(pk=place_id).name == "Station"

    assert admin.delete(f"/api/v1/admin/quick-places/{place_id}/").status_code == 204
    assert not QuickPlace.objects.exists()
    assert set(AuditLog.objects.values_list("action", flat=True)) >= {
        "api.create_quick_place", "api.update_quick_place", "api.delete_quick_place",
    }


def test_admin_rejects_invalid_coordinates():
    admin = client_for(make_user(Role.ADMIN))

    response = admin.post("/api/v1/admin/quick-places/", {**PLACE, "latitude": "95"}, format="json")

    assert response.status_code == 400


def test_customers_cannot_manage_places():
    customer = client_for(make_user(Role.CUSTOMER))

    assert customer.post("/api/v1/admin/quick-places/", PLACE, format="json").status_code == 403
    assert customer.get("/api/v1/admin/quick-places/").status_code == 403
