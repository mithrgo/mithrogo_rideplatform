from rest_framework import serializers
from rest_framework.response import Response
from rest_framework.views import APIView

from core import place_search
from apps.users.permissions import IsCustomer


class PlaceSearchQuerySerializer(serializers.Serializer):
    q = serializers.CharField(min_length=3, max_length=100, trim_whitespace=True)
    lat = serializers.FloatField(min_value=-90, max_value=90)
    lng = serializers.FloatField(min_value=-180, max_value=180)


class PlaceSearchView(APIView):
    """GET places/search/?q=&lat=&lng=. Only places within the backend search radius, nearest first."""

    permission_classes = [IsCustomer]

    def get(self, request):
        serializer = PlaceSearchQuerySerializer(data=request.query_params)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            return Response(place_search.search_nearby(data["q"], data["lat"], data["lng"]))
        except place_search.PlaceSearchUnavailable:
            return Response(
                {"detail": "Place search is unavailable right now. Try again.", "code": "place_search_unavailable"},
                status=503,
            )
