"""Account deletion, as the Play Store and App Store require.

Rides, payments and dues are kept for legal and accounting records (the database protects them),
so the user is anonymised rather than removed: personal data is wiped, the phone number is
released so it can sign up again as a new account, and every session is ended.
"""

import uuid

from django.db import transaction
from django.utils import timezone
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken

from core import audit
from core.exceptions import Conflict
from apps.users.models import Role, User


def deletion_blockers(user):
    """Reasons the account cannot be deleted right now (empty = it can)."""
    from apps.rides.models import ACTIVE_STATUSES, IN_PROGRESS_STATUSES, Ride

    reasons = []
    if user.role == Role.CUSTOMER:
        from apps.rides.services import outstanding_fees

        if Ride.objects.filter(customer=user, status__in=ACTIVE_STATUSES).exists():
            reasons.append("active_ride")
        if outstanding_fees(user).exists():
            reasons.append("unpaid_fees")
    elif user.role == Role.CAPTAIN:
        from apps.subscriptions.services import pending_dues_total
        from apps.wallets.services import get_wallet

        captain = getattr(user, "captain_profile", None)
        if captain is not None:
            if Ride.objects.filter(captain=captain, status__in=IN_PROGRESS_STATUSES).exists():
                reasons.append("active_ride")
            if pending_dues_total(captain) > 0:
                reasons.append("pending_dues")
            if get_wallet(captain).balance > 0:
                reasons.append("wallet_balance")
    elif user.role == Role.ADMIN:
        reasons.append("admin_account")
    return reasons


MESSAGES = {
    "active_ride": "Finish or cancel your current ride first.",
    "unpaid_fees": "Pay your pending cancellation fee first.",
    "pending_dues": "Clear your platform dues first.",
    "wallet_balance": "Your wallet still has money. Contact support to withdraw it first.",
    "admin_account": "Admin accounts are removed by another admin.",
}


def _placeholder_phone():
    # Fits the 16-character phone column and can never be a real number (no leading +).
    return "del" + uuid.uuid4().hex[:13]


@transaction.atomic
def delete_account(user, reason=""):
    user = User.objects.select_for_update().get(pk=user.pk)
    blockers = deletion_blockers(user)
    if blockers:
        raise Conflict(MESSAGES[blockers[0]], code=f"cannot_delete_{blockers[0]}")

    original_role = user.role
    user.phone = _placeholder_phone()
    user.email = None
    user.first_name = ""
    user.last_name = ""
    user.is_active = False
    user.deleted_at = timezone.now()
    user.set_unusable_password()
    user.save()

    if original_role == Role.CUSTOMER and hasattr(user, "customer_profile"):
        profile = user.customer_profile
        if profile.profile_photo:
            profile.profile_photo.delete(save=False)
        profile.profile_photo = None
        profile.emergency_contact_name = ""
        profile.emergency_contact_phone = ""
        profile.referral_code = None
        profile.save()
        user.saved_places.all().delete()
    if original_role == Role.CAPTAIN and hasattr(user, "captain_profile"):
        from apps.captains.models import OnlineStatus

        captain = user.captain_profile
        if captain.profile_photo:
            captain.profile_photo.delete(save=False)
        captain.profile_photo = None
        captain.address = ""
        captain.date_of_birth = None
        captain.online_status = OnlineStatus.OFFLINE
        captain.current_latitude = None
        captain.current_longitude = None
        captain.save()
        # KYC documents (licence, ID, photo) are personal data: remove the files and their records.
        for document in captain.kyc_documents.all():
            document.file.delete(save=False)
        captain.kyc_documents.all().delete()

    from apps.notifications.models import DeviceToken

    DeviceToken.objects.filter(user=user).delete()
    for token in OutstandingToken.objects.filter(user=user):
        BlacklistedToken.objects.get_or_create(token=token)
    audit.record(user, "account.deleted", user, {"role": original_role, "reason": (reason or "")[:200]})
    return user
