from django import forms
from django.contrib import admin, messages
from django.contrib.admin.helpers import ActionForm
from django.http import HttpResponse
from django.utils import timezone

from core import audit
from core.exceptions import DomainError
from core.models import AuditLog, PlatformConfig, QuickPlace, ServiceZone
from core.reports import to_csv


class ReasonActionForm(ActionForm):
    """Adds a free-text box next to the action dropdown, for actions that need a reason or note."""

    reason = forms.CharField(required=False, max_length=300, label="Reason / note",
                             widget=forms.TextInput(attrs={"size": 40, "placeholder": "Reason (needed for reject/cancel)"}))


def action_reason(request):
    return (request.POST.get("reason") or "").strip()


def csv_export_action(columns, filename):
    """Build an admin action that downloads the selected rows as CSV. columns: [(header, accessor), ...]."""

    def export(modeladmin, request, queryset):
        rows = []
        for obj in queryset:
            row = {}
            for header, accessor in columns:
                value = obj
                for part in accessor.split("__"):
                    value = getattr(value, part, None) if value is not None else None
                    if callable(value):
                        value = value()
                row[header] = value
            rows.append(row)
        AuditLog.objects.create(
            actor=request.user, action="admin.export_csv", model=queryset.model._meta.label_lower,
            object_id="-", changes={"rows": len(rows), "file": filename},
        )
        response = HttpResponse(to_csv(rows, [h for h, _ in columns]), content_type="text/csv")
        stamp = timezone.now().strftime("%Y%m%d-%H%M")
        response["Content-Disposition"] = f'attachment; filename="{filename}-{stamp}.csv"'
        return response

    export.short_description = "Export selected to CSV"
    export.__name__ = "export_csv"
    return export


class AuditedModelAdmin(admin.ModelAdmin):
    """Records every admin create/update/delete in AuditLog (who, what, before/after)."""

    def save_model(self, request, obj, form, change):
        changes = {}
        if change:
            changes = {
                field: [str(form.initial.get(field)), str(form.cleaned_data.get(field))]
                for field in form.changed_data
            }
        super().save_model(request, obj, form, change)
        audit.record(request.user, "admin.update" if change else "admin.create", obj, changes)

    def delete_model(self, request, obj):
        audit.record(request.user, "admin.delete", obj)
        super().delete_model(request, obj)


def run_action(modeladmin, request, queryset, action, handler, success_text):
    """Apply handler(obj, actor) to each row, audit each success, and report the outcome."""
    done, skipped = 0, []
    for obj in queryset:
        try:
            handler(obj, request.user)
        except DomainError as exc:
            skipped.append(f"{obj}: {exc.detail}")
            continue
        audit.record(request.user, f"admin.{action}", obj)
        done += 1
    if done:
        modeladmin.message_user(request, success_text.format(count=done), messages.SUCCESS)
    for line in skipped:
        modeladmin.message_user(request, line, messages.WARNING)


@admin.register(PlatformConfig)
class PlatformConfigAdmin(AuditedModelAdmin):
    fieldsets = (
        (
            "Matching and pricing",
            {
                "fields": (
                    "search_radius_km",
                    "offer_timeout_seconds",
                    "max_offer_attempts",
                    "location_freshness_seconds",
                    "road_distance_factor",
                    "average_speed_kmph",
                    "min_trip_km",
                )
            },
        ),
        (
            "Service area",
            {
                "fields": (
                    "restrict_to_service_area",
                    "service_area_name",
                    "service_area_latitude",
                    "service_area_longitude",
                    "service_area_radius_km",
                )
            },
        ),
        ("Captain plans", {"fields": ("unpaid_dues_limit", "service_timezone", "plan_expiry_reminder_minutes")}),
        ("Ride safety", {"fields": ("require_start_pin", "start_pin_max_attempts", "share_link_grace_minutes")}),
        (
            "Cancellations",
            {
                "fields": (
                    "customer_cancel_fee",
                    "cancel_free_window_seconds",
                    "customer_no_show_fee",
                    "no_show_wait_minutes",
                    "block_booking_on_unpaid_fees",
                )
            },
        ),
        (
            "Referrals",
            {"fields": ("referral_referee_reward", "referral_referrer_reward", "referral_reward_valid_days")},
        ),
    )

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def changelist_view(self, request, extra_context=None):
        config = PlatformConfig.load()
        return self.changeform_view(request, str(config.pk), "", extra_context)


@admin.register(ServiceZone)
class ServiceZoneAdmin(AuditedModelAdmin):
    list_display = ("name", "shape", "is_active")
    list_filter = ("shape", "is_active")
    fieldsets = (
        (None, {"fields": ("name", "shape", "is_active")}),
        ("Circle", {"fields": ("latitude", "longitude", "radius_km")}),
        ("Polygon", {"fields": ("polygon_points",)}),
    )


@admin.register(QuickPlace)
class QuickPlaceAdmin(AuditedModelAdmin):
    list_display = ("name", "icon", "sort_order", "is_active")
    list_editable = ("sort_order", "is_active")
    list_filter = ("is_active",)
    search_fields = ("name", "address")
    fields = ("name", "address", "latitude", "longitude", "icon", "sort_order", "is_active")


@admin.register(AuditLog)
class AuditLogAdmin(admin.ModelAdmin):
    list_display = ("created_at", "actor", "action", "model", "object_id")
    list_filter = ("action", "model")
    search_fields = ("object_id", "actor__phone")
    readonly_fields = ("actor", "action", "model", "object_id", "changes", "created_at")

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
