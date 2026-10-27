from rest_framework import serializers

from apps.captains.models import CaptainProfile, KycDocument
from apps.vehicles.models import VehicleType


class CaptainProfileSerializer(serializers.ModelSerializer):
    phone = serializers.CharField(source="user.phone", read_only=True)
    first_name = serializers.CharField(source="user.first_name", read_only=True)
    last_name = serializers.CharField(source="user.last_name", read_only=True)

    class Meta:
        model = CaptainProfile
        fields = [
            "phone",
            "first_name",
            "last_name",
            "date_of_birth",
            "address",
            "license_number",
            "license_expiry",
            "kyc_status",
            "kyc_rejection_reason",
            "online_status",
            "rating",
            "total_rides",
        ]
        read_only_fields = ["kyc_status", "kyc_rejection_reason", "online_status", "rating", "total_rides", "license_number", "license_expiry"]


class KycSubmitSerializer(serializers.Serializer):
    license_number = serializers.CharField(max_length=40)
    license_expiry = serializers.DateField()
    date_of_birth = serializers.DateField(required=False, allow_null=True)
    address = serializers.CharField(required=False, allow_blank=True)


class KycDocumentSerializer(serializers.ModelSerializer):
    class Meta:
        model = KycDocument
        fields = ["id", "doc_type", "file", "created_at"]
        read_only_fields = ["id", "created_at"]


class LocationSerializer(serializers.Serializer):
    latitude = serializers.DecimalField(max_digits=9, decimal_places=6, min_value=-90, max_value=90)
    longitude = serializers.DecimalField(max_digits=9, decimal_places=6, min_value=-180, max_value=180)
    heading = serializers.DecimalField(max_digits=6, decimal_places=2, required=False, allow_null=True)
    speed = serializers.DecimalField(max_digits=6, decimal_places=2, required=False, allow_null=True, min_value=0)


class VehicleOfDaySerializer(serializers.Serializer):
    vehicle_type = serializers.ChoiceField(choices=VehicleType.choices)
