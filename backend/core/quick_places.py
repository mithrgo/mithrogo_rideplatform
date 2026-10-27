from rest_framework import generics, serializers

from apps.users.permissions import IsCustomer
from core.models import QuickPlace


class CustomerQuickPlaceSerializer(serializers.ModelSerializer):
    class Meta:
        model = QuickPlace
        fields = ["id", "name", "address", "latitude", "longitude", "icon"]


class QuickPlaceListView(generics.ListAPIView):
    """The popular-destination cards for the customer home screen, in the order set in admin."""

    serializer_class = CustomerQuickPlaceSerializer
    permission_classes = [IsCustomer]
    pagination_class = None

    def get_queryset(self):
        return QuickPlace.objects.filter(is_active=True)
