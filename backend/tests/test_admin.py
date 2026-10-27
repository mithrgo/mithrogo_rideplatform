import pytest
from django.test import Client

from apps.captains.models import KycStatus
from core.models import AuditLog, PlatformConfig
from apps.users.models import User
from tests.helpers import make_captain, make_user, new_phone

from apps.users.models import Role


@pytest.fixture
def staff(db):
    admin = User.objects.create_superuser(phone=new_phone(), password="admin-pass-123-long")
    client = Client()
    client.force_login(admin)
    return client, admin


@pytest.mark.django_db
def test_dashboard_shows_operational_metrics(staff):
    client, _ = staff
    make_captain()

    response = client.get("/admin/")

    assert response.status_code == 200
    body = response.content.decode()
    assert "Operations dashboard" in body
    assert "Online captains" in body


@pytest.mark.django_db
@pytest.mark.parametrize(
    "url",
    [
        "/admin/users/user/",
        "/admin/captains/captainprofile/",
        "/admin/vehicles/vehicle/",
        "/admin/rides/ride/",
        "/admin/rides/fareconfig/",
        "/admin/rides/rating/",
        "/admin/subscriptions/subscriptionplan/",
        "/admin/subscriptions/captainsubscription/",
        "/admin/subscriptions/rideshareday/",
        "/admin/subscriptions/platformdue/",
        "/admin/payments/payment/",
        "/admin/support/supportticket/",
        "/admin/notifications/notification/",
        "/admin/core/auditlog/",
        "/admin/core/platformconfig/",
    ],
)
def test_admin_list_pages_load(staff, url):
    client, _ = staff

    response = client.get(url)

    assert response.status_code == 200


@pytest.mark.django_db
def test_approving_kyc_from_admin_is_audited(staff):
    client, admin = staff
    captain = make_captain(approved=False, plan=None, location=None, online=False)
    captain.kyc_status = KycStatus.UNDER_REVIEW
    captain.save(update_fields=["kyc_status"])

    response = client.post(
        "/admin/captains/captainprofile/",
        {"action": "approve_kyc", "_selected_action": [captain.pk]},
    )

    assert response.status_code == 302
    captain.refresh_from_db()
    assert captain.kyc_status == KycStatus.APPROVED
    entry = AuditLog.objects.get(action="admin.approve_kyc")
    assert entry.actor == admin
    assert entry.object_id == str(captain.pk)


@pytest.mark.django_db
def test_suspend_and_reactivate_captain_from_admin(staff):
    client, _ = staff
    captain = make_captain(location=None, online=False)

    client.post("/admin/captains/captainprofile/", {"action": "suspend_captains", "_selected_action": [captain.pk]})
    captain.refresh_from_db()
    suspended = captain.kyc_status

    client.post(
        "/admin/captains/captainprofile/", {"action": "reactivate_captains", "_selected_action": [captain.pk]}
    )
    captain.refresh_from_db()

    assert suspended == KycStatus.SUSPENDED
    assert captain.kyc_status == KycStatus.APPROVED


@pytest.mark.django_db
def test_platform_config_change_is_saved_and_audited(staff):
    client, _ = staff
    config = PlatformConfig.load()

    response = client.post(
        f"/admin/core/platformconfig/{config.pk}/change/",
        {
            "search_radius_km": "3.00",
            "offer_timeout_seconds": "20",
            "max_offer_attempts": "5",
            "location_freshness_seconds": "30",
            "road_distance_factor": "1.30",
            "average_speed_kmph": "20.00",
            "min_trip_km": "0.50",
            "unpaid_dues_limit": "500.00",
            "service_timezone": "Asia/Kolkata",
            "plan_expiry_reminder_minutes": "60",
            "require_start_pin": "on",
            "start_pin_max_attempts": "5",
            "share_link_grace_minutes": "30",
            "customer_cancel_fee": "0",
            "cancel_free_window_seconds": "120",
            "customer_no_show_fee": "0",
            "no_show_wait_minutes": "5",
            "block_booking_on_unpaid_fees": "on",
            "restrict_to_service_area": "on",
            "service_area_name": "Nizamabad",
            "service_area_latitude": "18.672500",
            "service_area_longitude": "78.094100",
            "service_area_radius_km": "20",
            "referral_referee_reward": "0",
            "referral_referrer_reward": "0",
            "referral_reward_valid_days": "30",
        },
    )

    assert response.status_code == 302
    config.refresh_from_db()
    assert config.offer_timeout_seconds == 20
    assert AuditLog.objects.filter(action="admin.update", model="core.platformconfig").exists()


@pytest.mark.django_db
def test_rides_cannot_be_added_or_edited_from_admin(staff):
    client, _ = staff

    assert client.get("/admin/rides/ride/add/").status_code == 403


@pytest.mark.django_db
def test_non_staff_users_cannot_open_admin():
    customer = make_user(Role.CUSTOMER)
    client = Client()
    client.force_login(customer)

    response = client.get("/admin/")

    assert response.status_code == 302
    assert "/admin/login/" in response["Location"]


@pytest.mark.django_db
def test_admin_pages_show_mithrgo_branding_and_live_rides_filter(staff):
    client, _ = staff

    page = client.get("/admin/")
    live = client.get("/admin/rides/ride/?live=active")

    assert "MithrGo Operations" in page.content.decode()
    assert live.status_code == 200
    assert "Live now" in live.content.decode()
