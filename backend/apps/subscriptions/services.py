import uuid
from datetime import timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from django.db import transaction
from django.db.models import Sum
from django.utils import timezone

from core.exceptions import Conflict, DomainError
from core.models import PlatformConfig
from apps.notifications.services import notify
from apps.payments.models import PaymentType
from apps.payments.services import create_payment
from apps.subscriptions.models import (
    CaptainSubscription,
    DayStatus,
    DueStatus,
    DueType,
    PlanType,
    PlatformDue,
    RideShareDay,
    SubscriptionPlan,
    SubStatus,
)


# ---------- helpers ----------

def service_today(now=None):
    """Business day in the configured timezone (ride-share counting boundary)."""
    now = now or timezone.now()
    return now.astimezone(ZoneInfo(PlatformConfig.load().service_timezone)).date()


def _ride_in_progress(captain):
    from apps.rides.models import IN_PROGRESS_STATUSES, Ride

    return Ride.objects.filter(captain=captain, status__in=IN_PROGRESS_STATUSES).exists()


def _latest_ride_share(captain):
    return (
        CaptainSubscription.objects.filter(captain=captain, plan__plan_type=PlanType.RIDE_SHARE)
        .order_by("-created_at")
        .first()
    )


def _active_ride_share(captain):
    return (
        CaptainSubscription.objects.filter(
            captain=captain, status=SubStatus.ACTIVE, plan__plan_type=PlanType.RIDE_SHARE
        )
        .select_related("plan")
        .first()
    )


def _get_plan(code, plan_type):
    plan = SubscriptionPlan.objects.filter(code=code, plan_type=plan_type, is_active=True).first()
    if plan is None:
        raise DomainError("This plan is not available.", code="plan_not_found")
    return plan


def pending_dues_total(captain):
    total = PlatformDue.objects.filter(captain=captain, status=DueStatus.PENDING).aggregate(total=Sum("amount"))
    return total["total"] or Decimal("0")


def active_subscription(captain):
    """The captain's ACTIVE subscription, expiring daily plans that have run out."""
    sub = (
        CaptainSubscription.objects.filter(captain=captain, status=SubStatus.ACTIVE)
        .select_related("plan")
        .order_by("-start_at")
        .first()
    )
    if sub is None:
        return None
    if sub.plan.plan_type == PlanType.DAILY_FLAT and sub.expires_at and sub.expires_at <= timezone.now():
        _expire(sub)
        return None
    return sub


def _expire(sub):
    """Mark a daily plan expired and tell the captain. Only the call that flips the status notifies."""
    updated = CaptainSubscription.objects.filter(pk=sub.pk, status=SubStatus.ACTIVE).update(
        status=SubStatus.EXPIRED, updated_at=timezone.now()
    )
    sub.status = SubStatus.EXPIRED
    if updated:
        notify(sub.captain.user, "SUBSCRIPTION_EXPIRED", "Plan expired", "Renew your daily plan to go online.")
    return bool(updated)


def plan_block_reasons(captain):
    """Reasons the captain cannot go online or take rides because of their plan (empty = fine)."""
    close_stale_days(captain)
    sub = active_subscription(captain)
    if sub is None:
        latest = CaptainSubscription.objects.filter(captain=captain).order_by("-created_at").first()
        if latest is not None and latest.status == SubStatus.EXPIRED:
            return ["plan_expired"]
        return ["no_active_plan"]

    reasons = []
    if PlatformDue.objects.filter(captain=captain, due_type=DueType.SHORTFALL_FEE, status=DueStatus.PENDING).exists():
        reasons.append("shortfall_fee_unpaid")
    if pending_dues_total(captain) > PlatformConfig.load().unpaid_dues_limit:
        reasons.append("dues_over_limit")
    return reasons


# ---------- plans and purchase ----------

def list_plans(vehicle_types):
    """Active plans for the given vehicle types only, so a Bike captain never sees Auto plans."""
    return SubscriptionPlan.objects.filter(is_active=True, vehicle_type__in=vehicle_types)


def _check_daily_purchase(captain, plan_code):
    """Every rule a daily plan purchase must pass, whichever way it is paid for."""
    plan = _get_plan(plan_code, PlanType.DAILY_FLAT)
    if _ride_in_progress(captain):
        raise Conflict("Finish your current ride before changing plans.", code="ride_in_progress")
    if not captain.vehicles.filter(vehicle_type=plan.vehicle_type, is_verified=True).exists():
        raise DomainError(
            f"You need a verified {plan.get_vehicle_type_display()} to buy this plan.", code="no_verified_vehicle"
        )
    current = active_subscription(captain)
    if current is not None and current.plan.plan_type == PlanType.DAILY_FLAT:
        raise Conflict(
            f"Your daily plan is active until {current.expires_at:%d %b %H:%M}.", code="plan_already_active"
        )
    return plan


def pay_daily_plan_from_wallet(captain, plan_code):
    """Buy a daily plan from the captain's wallet. Activates at once, since the money is already held."""
    from apps.captains.models import CaptainProfile
    from apps.wallets import services as wallet_services
    from apps.wallets.models import WalletTxnKind

    with transaction.atomic():
        # Lock the captain row first, so two purchases at once run one after the other and the
        # second one sees the first plan as already active instead of paying for a second plan.
        captain = CaptainProfile.objects.select_for_update().get(pk=captain.pk)
        plan = _check_daily_purchase(captain, plan_code)
        CaptainSubscription.objects.filter(captain=captain, status=SubStatus.PENDING).update(
            status=SubStatus.CANCELLED
        )
        sub = CaptainSubscription.objects.create(captain=captain, plan=plan, status=SubStatus.PENDING)
        wallet_services.debit(captain, plan.amount, WalletTxnKind.PLAN_PURCHASE, reference=f"sub:{sub.id}")
        activate_from_payment(sub, None)
    return sub


def pay_dues_from_wallet(captain):
    """Settle every pending platform due from the wallet in one step. Returns the amount paid."""
    from apps.wallets import services as wallet_services
    from apps.wallets.models import WalletTxnKind

    with transaction.atomic():
        dues = list(PlatformDue.objects.select_for_update().filter(captain=captain, status=DueStatus.PENDING))
        total = sum((due.amount for due in dues), Decimal("0"))
        if total <= 0:
            raise DomainError("You have no pending dues.", code="no_dues")
        wallet_services.debit(captain, total, WalletTxnKind.DUES_SETTLEMENT, reference=f"dues:{uuid.uuid4()}")
        PlatformDue.objects.filter(id__in=[due.id for due in dues]).update(
            status=DueStatus.SETTLED, settled_at=timezone.now()
        )
    return total


def create_daily_subscription_payment(captain, plan_code):
    """Start buying a daily plan. The subscription becomes ACTIVE only when the payment webhook confirms it."""
    plan = _check_daily_purchase(captain, plan_code)
    with transaction.atomic():
        CaptainSubscription.objects.filter(captain=captain, status=SubStatus.PENDING).update(
            status=SubStatus.CANCELLED
        )
        sub = CaptainSubscription.objects.create(captain=captain, plan=plan, status=SubStatus.PENDING)
        payment = create_payment(
            captain.user,
            PaymentType.CAPTAIN_SUBSCRIPTION,
            plan.amount,
            {"subscription_id": sub.id},
        )
        sub.payment = payment
        sub.save(update_fields=["payment", "updated_at"])
    return sub, payment


def switch_to_ride_share(captain, plan_code):
    """Move to the ride-share plan. No daily fee, so it activates at once."""
    plan = _get_plan(plan_code, PlanType.RIDE_SHARE)
    if _ride_in_progress(captain):
        raise Conflict("Finish your current ride before changing plans.", code="ride_in_progress")
    if not captain.vehicles.filter(vehicle_type=plan.vehicle_type, is_verified=True).exists():
        raise DomainError(
            f"You need a verified {plan.get_vehicle_type_display()} to choose this plan.", code="no_verified_vehicle"
        )
    close_stale_days(captain)
    current = active_subscription(captain)
    if current is not None and current.plan_id == plan.id:
        raise Conflict("You are already on this plan.", code="plan_already_active")
    with transaction.atomic():
        previous = _latest_ride_share(captain)
        carry_penalty = bool(previous and previous.penalty_pending)
        CaptainSubscription.objects.filter(captain=captain, status__in=[SubStatus.ACTIVE, SubStatus.PENDING]).update(
            status=SubStatus.CANCELLED
        )
        sub = CaptainSubscription.objects.create(
            captain=captain,
            plan=plan,
            status=SubStatus.ACTIVE,
            start_at=timezone.now(),
            penalty_pending=carry_penalty,
        )
    notify(captain.user, "PLAN_ACTIVE", "Ride-share plan active", "Your 1-in-5 ride-share plan is now active.")
    return sub


def activate_from_payment(subscription, payment):
    """Called by the payment webhook once a captain's subscription payment is confirmed."""
    with transaction.atomic():
        sub = CaptainSubscription.objects.select_for_update().select_related("plan").get(pk=subscription.pk)
        if sub.status == SubStatus.ACTIVE:
            return sub  # duplicate webhook: already applied
        if sub.status != SubStatus.PENDING:
            raise DomainError(
                "This plan request was cancelled after payment. Contact support for a refund.",
                code="subscription_cancelled",
            )
        now = timezone.now()
        if sub.plan.plan_type == PlanType.DAILY_FLAT:
            CaptainSubscription.objects.filter(captain=sub.captain, status=SubStatus.ACTIVE).update(
                status=SubStatus.CANCELLED
            )
            sub.start_at = now
            sub.expires_at = now + timedelta(hours=sub.plan.duration_hours)
        sub.status = SubStatus.ACTIVE
        sub.save(update_fields=["status", "start_at", "expires_at", "updated_at"])
    notify(sub.captain.user, "PAYMENT_SUCCESS", "Plan active", f"Your {sub.plan.name} plan is active.")
    return sub


def on_subscription_paid(payment):
    subscription = CaptainSubscription.objects.get(pk=payment.metadata["subscription_id"])
    activate_from_payment(subscription, payment)


def create_dues_payment(captain):
    """Pay all pending platform dues in one payment. The total is fixed when the payment is created."""
    dues = list(PlatformDue.objects.filter(captain=captain, status=DueStatus.PENDING))
    total = sum((due.amount for due in dues), Decimal("0"))
    if total <= 0:
        raise DomainError("You have no pending dues.", code="no_dues")
    return create_payment(
        captain.user,
        PaymentType.DUES_SETTLEMENT,
        total,
        {"due_ids": [due.id for due in dues]},
    )


def on_dues_paid(payment):
    PlatformDue.objects.filter(id__in=payment.metadata["due_ids"], status=DueStatus.PENDING).update(
        status=DueStatus.SETTLED, settled_at=timezone.now(), payment=payment
    )


def expire_subscriptions():
    """Expire daily plans past their end time. Run from run_periodic_jobs."""
    now = timezone.now()
    expired = CaptainSubscription.objects.filter(
        status=SubStatus.ACTIVE, plan__plan_type=PlanType.DAILY_FLAT, expires_at__lte=now
    ).select_related("captain__user")
    count = 0
    for sub in expired:
        count += _expire(sub)
    return count


def remind_expiring_subscriptions():
    """Warn captains shortly before a daily plan runs out, once per plan. Run from run_periodic_jobs."""
    now = timezone.now()
    window = timedelta(minutes=PlatformConfig.load().plan_expiry_reminder_minutes)
    due = CaptainSubscription.objects.filter(
        status=SubStatus.ACTIVE,
        plan__plan_type=PlanType.DAILY_FLAT,
        expires_at__gt=now,
        expires_at__lte=now + window,
        expiry_reminder_sent_at__isnull=True,
    ).select_related("captain__user")
    count = 0
    for sub in due:
        claimed = CaptainSubscription.objects.filter(pk=sub.pk, expiry_reminder_sent_at__isnull=True).update(
            expiry_reminder_sent_at=now
        )
        if not claimed:
            continue
        minutes = max(1, int((sub.expires_at - now).total_seconds() // 60))
        notify(
            sub.captain.user,
            "SUBSCRIPTION_EXPIRING",
            "Plan ending soon",
            f"Your daily plan ends in {minutes} minutes. Renew to keep taking rides.",
            {"subscription_id": sub.pk},
        )
        count += 1
    return count


# ---------- ride-share counting ----------

def _lock_today(captain, sub, now=None):
    today = service_today(now)
    day, _ = RideShareDay.objects.get_or_create(
        captain=captain,
        service_date=today,
        defaults={"subscription": sub, "qualifying_rides": sub.plan.qualifying_rides},
    )
    return RideShareDay.objects.select_for_update().get(pk=day.pk)


def _close_day(day):
    """End a day. A day with 1..(qualifying-1) completed rides and no platform ride is a shortfall."""
    shortfall = day.platform_ride_id is None and 1 <= day.completed_rides < day.qualifying_rides
    day.status = DayStatus.CLOSED
    day.shortfall = shortfall
    day.save(update_fields=["status", "shortfall", "updated_at"])
    if not shortfall:
        return
    fee = day.subscription.plan.shortfall_fee or Decimal("0")
    if fee > 0:
        PlatformDue.objects.create(captain=day.captain, due_type=DueType.SHORTFALL_FEE, amount=fee)
    latest = _latest_ride_share(day.captain)
    if latest is not None:
        latest.penalty_pending = True
        latest.save(update_fields=["penalty_pending", "updated_at"])
    notify(
        day.captain.user,
        "SHORTFALL_FEE",
        "Shortfall fee",
        f"You completed fewer than {day.qualifying_rides} rides. A ₹{fee} fee is due and your first ride tomorrow is taken.",
    )


def close_stale_days(captain):
    """Close this captain's open days from before today. Safe to call repeatedly."""
    today = service_today()
    with transaction.atomic():
        stale = list(
            RideShareDay.objects.filter(captain=captain, status=DayStatus.OPEN, service_date__lt=today)
            .order_by("service_date")
            .values_list("id", flat=True)
        )
        for day_id in stale:
            _close_day(RideShareDay.objects.select_for_update().get(pk=day_id))
    return len(stale)


def close_all_stale_days():
    """Close stale days for every captain. Run from run_periodic_jobs."""
    from apps.captains.models import CaptainProfile

    closed = 0
    captain_ids = RideShareDay.objects.filter(status=DayStatus.OPEN).values_list("captain_id", flat=True).distinct()
    for captain in CaptainProfile.objects.filter(pk__in=list(captain_ids)):
        closed += close_stale_days(captain)
    return closed


def record_completed_ride(ride):
    """Decide whether this completed ride is the platform's one ride for the day.

    Must run inside the ride-completion transaction; the RideShareDay row lock makes
    two simultaneous completions unable to both take a ride. The caller saves the ride.
    Returns the share reason, or None when nothing is taken.
    """
    sub = _active_ride_share(ride.captain)
    if sub is None:
        return None
    close_stale_days(ride.captain)
    day = _lock_today(ride.captain, sub)
    day.completed_rides += 1

    reason = None
    if day.platform_ride_id is not None:
        reason = None  # the platform already took today's ride; this ride is the captain's
    elif sub.penalty_pending:
        reason = "PENALTY_FIRST_RIDE"
        sub.penalty_pending = False
        sub.save(update_fields=["penalty_pending", "updated_at"])
    elif day.surrendered_ride_id == ride.id:
        reason = "SURRENDERED"
    elif day.completed_rides >= day.qualifying_rides:
        reason = "AUTO_5TH"

    if reason:
        day.platform_ride = ride
        ride.is_platform_ride = True
        ride.share_reason = reason
        ride.platform_share_amount = ride.final_fare
        PlatformDue.objects.create(
            captain=ride.captain,
            ride=ride,
            due_type=DueType.RIDE_SHARE,
            amount=ride.final_fare,
        )
    day.save(update_fields=["completed_rides", "platform_ride", "updated_at"])
    return reason


def surrender_ride(captain, ride):
    """Captain gives today's platform ride to one of their first qualifying-1 rides. Once per day."""
    from apps.rides.models import IN_PROGRESS_STATUSES

    sub = _active_ride_share(captain)
    if sub is None:
        raise Conflict("Surrendering a ride is only available on the ride-share plan.", code="not_ride_share")
    if ride.captain_id != captain.id or ride.status not in IN_PROGRESS_STATUSES:
        raise Conflict("Only the ride you are on can be surrendered.", code="invalid_ride")

    with transaction.atomic():
        day = _lock_today(captain, sub)
        if day.platform_ride_id is not None:
            raise Conflict("Today's platform ride has already been taken.", code="platform_ride_taken")
        if day.surrendered_ride_id is not None:
            raise Conflict("You already surrendered a ride today.", code="already_surrendered")
        if day.completed_rides >= day.qualifying_rides - 1:
            raise Conflict(
                f"You can surrender only one of your first {day.qualifying_rides - 1} rides.",
                code="surrender_window_closed",
            )
        day.surrendered_ride = ride
        day.save(update_fields=["surrendered_ride", "updated_at"])
    return day


def release_surrender(ride):
    """A surrendered ride was cancelled: the captain may surrender again later today."""
    RideShareDay.objects.filter(surrendered_ride=ride).update(surrendered_ride=None)


def todays_summary(captain):
    sub = _active_ride_share(captain)
    if sub is None:
        return None
    day = RideShareDay.objects.filter(captain=captain, service_date=service_today()).first()
    return {
        "qualifying_rides": sub.plan.qualifying_rides,
        "completed_rides": day.completed_rides if day else 0,
        "platform_ride_taken": bool(day and day.platform_ride_id),
        "surrendered": bool(day and day.surrendered_ride_id),
    }


# ---------- admin actions on dues ----------

def waive_due(due, actor=None):
    if due.status != DueStatus.PENDING:
        raise Conflict("Only pending dues can be waived.", code="not_pending")
    due.status = DueStatus.WAIVED
    due.save(update_fields=["status", "updated_at"])
    return due


def settle_due_offline(due, actor=None):
    """Admin confirms the captain paid in cash or by bank transfer, outside the gateway."""
    if due.status != DueStatus.PENDING:
        raise Conflict("Only pending dues can be settled.", code="not_pending")
    due.status = DueStatus.SETTLED
    due.settled_at = timezone.now()
    due.save(update_fields=["status", "settled_at", "updated_at"])
    return due
