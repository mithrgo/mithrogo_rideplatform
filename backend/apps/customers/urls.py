from django.urls import path

from apps.customers.places import SavedPlaceDetailView, SavedPlaceListView
from apps.customers.views import CustomerProfileView
from core.quick_places import QuickPlaceListView
from apps.promotions.views import ApplyReferralView, AvailablePromosView, ReferralView

urlpatterns = [
    path("profile/", CustomerProfileView.as_view(), name="customer-profile"),
    path("places/", SavedPlaceListView.as_view(), name="customer-places"),
    path("places/<int:pk>/", SavedPlaceDetailView.as_view(), name="customer-place-detail"),
    path("quick-places/", QuickPlaceListView.as_view(), name="customer-quick-places"),
    path("promos/", AvailablePromosView.as_view(), name="customer-promos"),
    path("referral/", ReferralView.as_view(), name="customer-referral"),
    path("referral/apply/", ApplyReferralView.as_view(), name="customer-referral-apply"),
]
