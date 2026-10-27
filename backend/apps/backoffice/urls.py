from django.urls import path

from apps.backoffice import views as v

urlpatterns = [
    path("dashboard/", v.DashboardView.as_view(), name="bo-dashboard"),
    path("reports/daily/", v.DailyReportView.as_view(), name="bo-report-daily"),
    path("reports/captain-earnings/", v.CaptainEarningsReportView.as_view(), name="bo-report-earnings"),

    path("customers/", v.CustomerListView.as_view(), name="bo-customers"),
    path("customers/<uuid:pk>/", v.CustomerDetailView.as_view(), name="bo-customer"),
    path("customers/<uuid:pk>/suspend/", v.UserActiveView.as_view(active=False), name="bo-customer-suspend"),
    path("customers/<uuid:pk>/reactivate/", v.UserActiveView.as_view(active=True), name="bo-customer-reactivate"),

    path("captains/", v.CaptainListView.as_view(), name="bo-captains"),
    path("captains/<int:pk>/", v.CaptainDetailView.as_view(), name="bo-captain"),
    path("captains/<int:pk>/approve/", v.CaptainActionView.as_view(action="approve"), name="bo-captain-approve"),
    path("captains/<int:pk>/reject/", v.CaptainActionView.as_view(action="reject"), name="bo-captain-reject"),
    path("captains/<int:pk>/suspend/", v.CaptainActionView.as_view(action="suspend"), name="bo-captain-suspend"),
    path("captains/<int:pk>/reactivate/", v.CaptainActionView.as_view(action="reactivate"),
         name="bo-captain-reactivate"),
    path("vehicles/<int:pk>/verify/", v.VehicleActionView.as_view(verify=True), name="bo-vehicle-verify"),
    path("vehicles/<int:pk>/unverify/", v.VehicleActionView.as_view(verify=False), name="bo-vehicle-unverify"),

    path("rides/", v.RideListView.as_view(), name="bo-rides"),
    path("rides/live/", v.LiveRidesView.as_view(), name="bo-rides-live"),
    path("rides/<uuid:pk>/", v.RideDetailView.as_view(), name="bo-ride"),
    path("rides/<uuid:pk>/route/", v.RideRouteView.as_view(), name="bo-ride-route"),
    path("rides/<uuid:pk>/cancel/", v.RideCancelView.as_view(), name="bo-ride-cancel"),
    path("rides/<uuid:pk>/waive-fee/", v.RideWaiveFeeView.as_view(), name="bo-ride-waive-fee"),

    path("payments/", v.PaymentListView.as_view(), name="bo-payments"),
    path("subscriptions/", v.SubscriptionListView.as_view(), name="bo-subscriptions"),
    path("dues/", v.DueListView.as_view(), name="bo-dues"),
    path("dues/<int:pk>/waive/", v.DueActionView.as_view(waive=True), name="bo-due-waive"),
    path("dues/<int:pk>/settle/", v.DueActionView.as_view(waive=False), name="bo-due-settle"),

    path("tickets/", v.TicketListView.as_view(), name="bo-tickets"),
    path("tickets/<int:pk>/", v.TicketDetailView.as_view(), name="bo-ticket"),
    path("tickets/<int:pk>/reply/", v.TicketReplyView.as_view(), name="bo-ticket-reply"),
    path("tickets/<int:pk>/status/", v.TicketStatusView.as_view(), name="bo-ticket-status"),
    path("sos/", v.SosListView.as_view(), name="bo-sos"),
    path("sos/<int:pk>/acknowledge/", v.SosActionView.as_view(resolve=False), name="bo-sos-ack"),
    path("sos/<int:pk>/resolve/", v.SosActionView.as_view(resolve=True), name="bo-sos-resolve"),

    path("promos/", v.PromoListView.as_view(), name="bo-promos"),
    path("promos/<int:pk>/", v.PromoDetailView.as_view(), name="bo-promo"),
    path("fares/", v.FareListView.as_view(), name="bo-fares"),
    path("fares/<int:pk>/", v.FareDetailView.as_view(), name="bo-fare"),
    path("quick-places/", v.QuickPlaceListView.as_view(), name="bo-quick-places"),
    path("quick-places/<int:pk>/", v.QuickPlaceDetailView.as_view(), name="bo-quick-place"),
    path("plans/", v.PlanListView.as_view(), name="bo-plans"),
    path("plans/<int:pk>/", v.PlanDetailView.as_view(), name="bo-plan"),
    path("config/", v.PlatformConfigView.as_view(), name="bo-config"),
    path("audit-log/", v.AuditLogView.as_view(), name="bo-audit-log"),
    path("broadcast/", v.BroadcastView.as_view(), name="bo-broadcast"),
]
