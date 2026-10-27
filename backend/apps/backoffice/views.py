"""Admin REST API for the admin web app. Every endpoint needs an ADMIN token; every change is audit-logged."""

from django.db import transaction
from django.db.models import Count, Q
from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from rest_framework import generics, serializers, status
from rest_framework.pagination import LimitOffsetPagination
from rest_framework.response import Response
from rest_framework.views import APIView

from core import audit, reports
from core.exceptions import DomainError
from core.metrics import dashboard_metrics
from core.models import AuditLog, PlatformConfig, QuickPlace
from apps.backoffice import serializers as s
from apps.backoffice.permissions import IsAdminRole
from apps.captains import services as captain_services
from apps.captains.models import CaptainProfile
from apps.notifications.services import notify
from apps.payments.models import Payment
from apps.promotions.models import PromoCode, RedemptionStatus
from apps.rides import services as ride_services
from apps.rides.models import ACTIVE_STATUSES, CancelledBy, FareConfig, Ride
from apps.subscriptions import services as subscription_services
from apps.subscriptions.models import CaptainSubscription, PlatformDue, SubscriptionPlan
from apps.support import services as support_services
from apps.support.models import SosAlert, SupportTicket, TicketStatus
from apps.users.models import Role, User
from apps.vehicles import services as vehicle_services
from apps.vehicles.models import Vehicle


class AdminPagination(LimitOffsetPagination):
    default_limit = 50
    max_limit = 200


class AdminView(APIView):
    permission_classes = [IsAdminRole]


class AdminListView(generics.ListAPIView):
    """List with ?search=, field filters (filter_params), and limit/offset pagination."""

    permission_classes = [IsAdminRole]
    pagination_class = AdminPagination
    search_fields = ()
    filter_params = {}  # query param -> ORM lookup

    def filter_queryset(self, queryset):
        params = self.request.query_params
        term = params.get("search", "").strip()
        if term and self.search_fields:
            query = Q()
            for field in self.search_fields:
                query |= Q(**{f"{field}__icontains": term})
            queryset = queryset.filter(query)
        for param, lookup in self.filter_params.items():
            value = params.get(param)
            if value not in (None, ""):
                if value in ("true", "false"):
                    value = value == "true"
                queryset = queryset.filter(**{lookup: value})
        return queryset


def _act(request, obj, action, handler, changes=None):
    """Run an admin action atomically and audit it. DomainErrors become normal API errors."""
    with transaction.atomic():
        result = handler()
        audit.record(request.user, f"api.{action}", obj, changes or {})
    return result


class ReasonSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=300, required=False, allow_blank=True, default="")


def _reason(request, required=False):
    serializer = ReasonSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    reason = serializer.validated_data["reason"].strip()
    if required and not reason:
        raise DomainError("Give a reason.", code="reason_required")
    return reason


# ---------- dashboard and reports ----------

class DashboardView(AdminView):
    def get(self, request):
        metrics = {k: str(v) if not isinstance(v, int) else v for k, v in dashboard_metrics().items()}
        start, end = reports.parse_range(default_days=7)
        return Response({"metrics": metrics, "last_7_days": reports.daily_report(start, end)})


class DailyReportView(AdminView):
    """?from=YYYY-MM-DD&to=YYYY-MM-DD&export=csv"""

    def get(self, request):
        start, end = reports.parse_range(request.query_params.get("from"), request.query_params.get("to"))
        rows = reports.daily_report(start, end)
        if request.query_params.get("export") == "csv":
            return _csv(rows, f"daily-report-{start}-to-{end}.csv")
        return Response({"from": start, "to": end, "rows": rows, "totals": reports.report_totals(rows)})


class CaptainEarningsReportView(AdminView):
    def get(self, request):
        start, end = reports.parse_range(request.query_params.get("from"), request.query_params.get("to"))
        rows = reports.captain_earnings_report(start, end)
        if request.query_params.get("export") == "csv":
            return _csv(rows, f"captain-earnings-{start}-to-{end}.csv")
        return Response({"from": start, "to": end, "rows": rows})


def _csv(rows, filename):
    response = HttpResponse(reports.to_csv(rows), content_type="text/csv")
    response["Content-Disposition"] = f'attachment; filename="{filename}"'
    return response


# ---------- customers ----------

class CustomerListView(AdminListView):
    serializer_class = s.CustomerSerializer
    search_fields = ("phone", "first_name", "last_name", "email")
    filter_params = {"is_active": "is_active"}

    def get_queryset(self):
        return (
            User.objects.filter(role=Role.CUSTOMER)
            .select_related("customer_profile")
            .annotate(total_rides=Count("rides"), completed_rides=Count("rides", filter=Q(rides__status="COMPLETED")))
            .order_by("-created_at")
        )


class CustomerDetailView(generics.RetrieveAPIView):
    permission_classes = [IsAdminRole]
    serializer_class = s.CustomerSerializer

    def get_queryset(self):
        return CustomerListView.get_queryset(self)


class UserActiveView(AdminView):
    """POST .../suspend/ or .../reactivate/ for a customer account."""

    active = None

    def post(self, request, pk):
        user = get_object_or_404(User, pk=pk, role=Role.CUSTOMER, deleted_at__isnull=True)

        def handler():
            user.is_active = self.active
            user.save(update_fields=["is_active", "updated_at"])

        _act(request, user, "reactivate_user" if self.active else "suspend_user", handler)
        return Response(s.UserBriefSerializer(user).data)


# ---------- captains and vehicles ----------

class CaptainListView(AdminListView):
    serializer_class = s.CaptainSerializer
    search_fields = ("user__phone", "user__first_name", "user__last_name", "license_number")
    filter_params = {"kyc_status": "kyc_status", "online_status": "online_status"}

    def get_queryset(self):
        return CaptainProfile.objects.select_related("user").order_by("-created_at")


class CaptainDetailView(generics.RetrieveAPIView):
    permission_classes = [IsAdminRole]
    serializer_class = s.CaptainDetailSerializer
    queryset = CaptainProfile.objects.select_related("user").prefetch_related("vehicles", "kyc_documents")


class CaptainActionView(AdminView):
    """POST captains/{id}/{approve|reject|suspend|reactivate}/. Reject needs {"reason"}."""

    action = None

    def post(self, request, pk):
        captain = get_object_or_404(CaptainProfile.objects.select_related("user"), pk=pk)
        if self.action == "reject":
            reason = _reason(request, required=True)
            _act(request, captain, "reject_kyc", lambda: captain_services.reject_kyc(captain, request.user, reason),
                 {"reason": reason})
        else:
            handler = {
                "approve": captain_services.approve_kyc,
                "suspend": captain_services.suspend_captain,
                "reactivate": captain_services.reactivate_captain,
            }[self.action]
            _act(request, captain, f"{self.action}_captain", lambda: handler(captain, request.user))
        captain.refresh_from_db()
        return Response(s.CaptainDetailSerializer(captain, context={"request": request}).data)


class VehicleActionView(AdminView):
    verify = True

    def post(self, request, pk):
        vehicle = get_object_or_404(Vehicle, pk=pk)
        handler = vehicle_services.verify_vehicle if self.verify else vehicle_services.unverify_vehicle
        _act(request, vehicle, "verify_vehicle" if self.verify else "unverify_vehicle",
             lambda: handler(vehicle, request.user))
        return Response(s.VehicleSerializer(vehicle).data)


# ---------- rides ----------

class RideListView(AdminListView):
    serializer_class = s.RideListSerializer
    search_fields = ("id", "customer__phone", "captain__user__phone", "pickup_address", "drop_address")
    filter_params = {
        "status": "status",
        "vehicle_type": "vehicle_type",
        "payment_method": "payment_method",
        "captain": "captain_id",
        "customer": "customer_id",
        "from": "requested_at__date__gte",
        "to": "requested_at__date__lte",
    }

    def get_queryset(self):
        return Ride.objects.select_related("customer", "captain__user").order_by("-requested_at")


class LiveRidesView(AdminView):
    """Every active ride with the captain's latest position, for the live map."""

    def get(self, request):
        rides = Ride.objects.filter(status__in=ACTIVE_STATUSES).select_related("customer", "captain__user")
        data = []
        for ride in rides:
            row = s.RideListSerializer(ride).data
            captain = ride.captain
            row["captain_location"] = (
                {"latitude": captain.current_latitude, "longitude": captain.current_longitude,
                 "updated_at": captain.last_location_at}
                if captain and captain.current_latitude is not None else None
            )
            data.append(row)
        online = CaptainProfile.objects.filter(
            online_status__in=["ONLINE", "BUSY"], current_latitude__isnull=False
        ).select_related("user")
        captains = [
            {"id": c.pk, "name": c.user.full_name or c.user.phone, "status": c.online_status,
             "latitude": c.current_latitude, "longitude": c.current_longitude, "updated_at": c.last_location_at}
            for c in online
        ]
        return Response({"rides": data, "captains": captains})


class RideDetailView(generics.RetrieveAPIView):
    permission_classes = [IsAdminRole]
    serializer_class = s.RideDetailSerializer
    queryset = Ride.objects.select_related("customer", "captain__user").prefetch_related(
        "events__actor", "offers__captain__user"
    )


class RideRouteView(AdminView):
    """The captain's recorded location trail for a ride."""

    def get(self, request, pk):
        ride = get_object_or_404(Ride, pk=pk)
        points = ride.locations.order_by("recorded_at")[:2000]
        return Response(s.RideLocationSerializer(points, many=True).data)


class RideCancelView(AdminView):
    def post(self, request, pk):
        ride = get_object_or_404(Ride, pk=pk)
        reason = _reason(request, required=True)
        ride = _act(request, ride, "cancel_ride", lambda: ride_services.cancel_ride(
            ride, actor=request.user, reason="CANCELLED_BY_ADMIN", cancelled_by=CancelledBy.ADMIN, note=reason
        ), {"reason": reason})
        return Response(s.RideListSerializer(ride).data)


class RideWaiveFeeView(AdminView):
    def post(self, request, pk):
        ride = get_object_or_404(Ride, pk=pk)
        ride = _act(request, ride, "waive_cancellation_fee", lambda: ride_services.waive_fee(ride, request.user))
        return Response(s.RideListSerializer(ride).data)


# ---------- money ----------

class PaymentListView(AdminListView):
    serializer_class = s.PaymentSerializer
    search_fields = ("provider_order_id", "provider_payment_id", "user__phone")
    filter_params = {"status": "status", "payment_type": "payment_type", "from": "created_at__date__gte",
                     "to": "created_at__date__lte"}

    def get_queryset(self):
        return Payment.objects.select_related("user").order_by("-created_at")


class SubscriptionListView(AdminListView):
    serializer_class = s.SubscriptionSerializer
    search_fields = ("captain__user__phone",)
    filter_params = {"status": "status", "plan": "plan__code", "captain": "captain_id"}

    def get_queryset(self):
        return CaptainSubscription.objects.select_related("captain__user", "plan").order_by("-created_at")


class DueListView(AdminListView):
    serializer_class = s.DueSerializer
    search_fields = ("captain__user__phone",)
    filter_params = {"status": "status", "due_type": "due_type", "captain": "captain_id"}

    def get_queryset(self):
        return PlatformDue.objects.select_related("captain__user").order_by("-created_at")


class DueActionView(AdminView):
    waive = True

    def post(self, request, pk):
        due = get_object_or_404(PlatformDue, pk=pk)
        handler = subscription_services.waive_due if self.waive else subscription_services.settle_due_offline
        _act(request, due, "waive_due" if self.waive else "settle_due_offline", lambda: handler(due, request.user))
        return Response(s.DueSerializer(due).data)


# ---------- support and safety ----------

class TicketListView(AdminListView):
    serializer_class = s.TicketSerializer
    search_fields = ("user__phone", "description")
    filter_params = {"status": "status", "category": "category"}

    def get_queryset(self):
        return SupportTicket.objects.select_related("user").order_by("-created_at")


class TicketDetailView(generics.RetrieveAPIView):
    permission_classes = [IsAdminRole]
    serializer_class = s.TicketDetailSerializer
    queryset = SupportTicket.objects.select_related("user").prefetch_related("messages__author")


class ReplySerializer(serializers.Serializer):
    body = serializers.CharField(max_length=2000)


class TicketReplyView(AdminView):
    def post(self, request, pk):
        ticket = get_object_or_404(SupportTicket, pk=pk)
        serializer = ReplySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        message = _act(request, ticket, "ticket_reply", lambda: support_services.add_message(
            ticket, request.user, serializer.validated_data["body"], True
        ))
        return Response(s.TicketMessageSerializer(message).data, status=status.HTTP_201_CREATED)


class TicketStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=TicketStatus.choices)
    note = serializers.CharField(max_length=2000, required=False, allow_blank=True, default="")


class TicketStatusView(AdminView):
    def post(self, request, pk):
        ticket = get_object_or_404(SupportTicket, pk=pk)
        serializer = TicketStatusSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        _act(request, ticket, "ticket_status", lambda: support_services.set_ticket_status(
            ticket, data["status"], data["note"], request.user
        ), {"status": data["status"]})
        return Response(s.TicketSerializer(ticket).data)


class SosListView(AdminListView):
    serializer_class = s.SosSerializer
    filter_params = {"status": "status"}
    search_fields = ("user__phone",)

    def get_queryset(self):
        return SosAlert.objects.select_related("user", "handled_by", "ride").order_by("-created_at")


class SosActionView(AdminView):
    resolve = False

    def post(self, request, pk):
        alert = get_object_or_404(SosAlert, pk=pk)
        if self.resolve:
            note = _reason(request)
            _act(request, alert, "resolve_sos", lambda: support_services.resolve_sos(alert, request.user, note))
        else:
            _act(request, alert, "acknowledge_sos", lambda: support_services.acknowledge_sos(alert, request.user))
        return Response(s.SosSerializer(alert).data)


# ---------- configuration ----------

class PromoListView(AdminListView, generics.CreateAPIView):
    serializer_class = s.PromoCodeSerializer
    search_fields = ("code", "description")
    filter_params = {"is_active": "is_active"}

    def get_queryset(self):
        return PromoCode.objects.filter(assigned_user__isnull=True).annotate(
            times_used=Count("redemptions", filter=Q(redemptions__status=RedemptionStatus.APPLIED))
        ).order_by("-created_at")

    def perform_create(self, serializer):
        promo = serializer.save()
        audit.record(self.request.user, "api.create_promo", promo, {"code": promo.code})


class _AuditedUpdateView(generics.RetrieveUpdateAPIView):
    permission_classes = [IsAdminRole]
    http_method_names = ["get", "patch"]
    audit_action = "update"

    def perform_update(self, serializer):
        before = {k: str(getattr(serializer.instance, k)) for k in serializer.validated_data}
        obj = serializer.save()
        changes = {k: [before[k], str(getattr(obj, k))] for k in serializer.validated_data if before[k] != str(getattr(obj, k))}
        audit.record(self.request.user, f"api.{self.audit_action}", obj, changes)


class PromoDetailView(_AuditedUpdateView):
    serializer_class = s.PromoCodeSerializer
    audit_action = "update_promo"

    def get_queryset(self):
        return PromoListView.get_queryset(self)


class FareListView(generics.ListAPIView):
    permission_classes = [IsAdminRole]
    serializer_class = s.FareConfigSerializer
    queryset = FareConfig.objects.order_by("vehicle_type")


class FareDetailView(_AuditedUpdateView):
    serializer_class = s.FareConfigSerializer
    queryset = FareConfig.objects.all()
    audit_action = "update_fare"


class QuickPlaceListView(generics.ListCreateAPIView):
    permission_classes = [IsAdminRole]
    serializer_class = s.QuickPlaceSerializer
    pagination_class = None
    queryset = QuickPlace.objects.all()

    def perform_create(self, serializer):
        place = serializer.save()
        audit.record(self.request.user, "api.create_quick_place", place, {"name": place.name})


class QuickPlaceDetailView(_AuditedUpdateView, generics.DestroyAPIView):
    http_method_names = ["get", "patch", "delete"]
    serializer_class = s.QuickPlaceSerializer
    queryset = QuickPlace.objects.all()
    audit_action = "update_quick_place"

    def perform_destroy(self, instance):
        audit.record(self.request.user, "api.delete_quick_place", instance, {"name": instance.name})
        instance.delete()


class PlanListView(generics.ListAPIView):
    permission_classes = [IsAdminRole]
    serializer_class = s.PlanSerializer
    queryset = SubscriptionPlan.objects.order_by("code")


class PlanDetailView(_AuditedUpdateView):
    serializer_class = s.PlanSerializer
    queryset = SubscriptionPlan.objects.all()
    audit_action = "update_plan"

    def perform_update(self, serializer):
        # Run the model's own rules (e.g. ride-share plans need a shortfall fee).
        instance = serializer.instance
        for key, value in serializer.validated_data.items():
            setattr(instance, key, value)
        from django.core.exceptions import ValidationError

        try:
            instance.clean()
        except ValidationError as exc:
            raise serializers.ValidationError(exc.message_dict)
        instance.refresh_from_db()
        super().perform_update(serializer)


class PlatformConfigView(_AuditedUpdateView):
    serializer_class = s.PlatformConfigSerializer
    audit_action = "update_platform_config"

    def get_object(self):
        return PlatformConfig.load()


class AuditLogView(AdminListView):
    serializer_class = s.AuditLogSerializer
    search_fields = ("object_id", "actor__phone", "action")
    filter_params = {"action": "action", "model": "model"}

    def get_queryset(self):
        return AuditLog.objects.select_related("actor").order_by("-created_at")


class BroadcastSerializer(serializers.Serializer):
    audience = serializers.ChoiceField(choices=["CUSTOMERS", "CAPTAINS", "ALL"])
    title = serializers.CharField(max_length=120)
    message = serializers.CharField(max_length=500)


class BroadcastView(AdminView):
    """Send an in-app (and push) announcement to customers, captains, or everyone."""

    def post(self, request):
        serializer = BroadcastSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        roles = {"CUSTOMERS": [Role.CUSTOMER], "CAPTAINS": [Role.CAPTAIN], "ALL": [Role.CUSTOMER, Role.CAPTAIN]}
        users = User.objects.filter(role__in=roles[data["audience"]], is_active=True)
        count = 0
        for user in users.iterator():
            notify(user, "ANNOUNCEMENT", data["title"], data["message"])
            count += 1
        AuditLog.objects.create(
            actor=request.user, action="api.broadcast", model="notifications.notification", object_id="-",
            changes={**data, "recipients": count},
        )
        return Response({"recipients": count}, status=status.HTTP_201_CREATED)
