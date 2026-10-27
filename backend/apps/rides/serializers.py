from rest_framework import serializers

from apps.rides.models import CaptainCancelReason, CustomerCancelReason, PaymentMethod, Ride, RideOffer
from apps.vehicles.models import VehicleType


class CoordinatesMixin(serializers.Serializer):
    pickup_latitude = serializers.DecimalField(max_digits=9, decimal_places=6, min_value=-90, max_value=90)
    pickup_longitude = serializers.DecimalField(max_digits=9, decimal_places=6, min_value=-180, max_value=180)
    drop_latitude = serializers.DecimalField(max_digits=9, decimal_places=6, min_value=-90, max_value=90)
    drop_longitude = serializers.DecimalField(max_digits=9, decimal_places=6, min_value=-180, max_value=180)


class EstimateSerializer(CoordinatesMixin):
    vehicle_type = serializers.ChoiceField(choices=VehicleType.choices)
    promo_code = serializers.CharField(max_length=24, required=False, allow_blank=True)


class RideCreateSerializer(EstimateSerializer):
    pickup_address = serializers.CharField(max_length=255)
    drop_address = serializers.CharField(max_length=255)
    payment_method = serializers.ChoiceField(choices=PaymentMethod.choices, default=PaymentMethod.ONLINE)
    # Where the person booking is. Differs from the pickup when booking for a friend.
    device_latitude = serializers.DecimalField(
        max_digits=9, decimal_places=6, min_value=-90, max_value=90, required=False
    )
    device_longitude = serializers.DecimalField(
        max_digits=9, decimal_places=6, min_value=-180, max_value=180, required=False
    )


class RatingInputSerializer(serializers.Serializer):
    rating = serializers.IntegerField(min_value=1, max_value=5)
    comment = serializers.CharField(max_length=500, required=False, allow_blank=True, default="")


class CustomerCancelSerializer(serializers.Serializer):
    reason = serializers.ChoiceField(choices=CustomerCancelReason.choices, default=CustomerCancelReason.OTHER)
    note = serializers.CharField(max_length=300, required=False, allow_blank=True, default="")


class CaptainCancelSerializer(serializers.Serializer):
    reason = serializers.ChoiceField(choices=CaptainCancelReason.choices)
    note = serializers.CharField(max_length=300, required=False, allow_blank=True, default="")


class StartRideSerializer(serializers.Serializer):
    pin = serializers.CharField(max_length=4, required=False, allow_blank=True, default="")


class RatingOutputSerializer(serializers.Serializer):
    rating = serializers.IntegerField()
    comment = serializers.CharField()


PIN_VISIBLE = {"SEARCHING", "ACCEPTED", "CAPTAIN_ARRIVED"}


class RideSerializer(serializers.ModelSerializer):
    """The customer's view of a ride."""

    captain = serializers.SerializerMethodField()
    start_pin = serializers.SerializerMethodField()
    payable_fare = serializers.DecimalField(max_digits=10, decimal_places=2, read_only=True)
    is_rated = serializers.SerializerMethodField()
    my_rating = serializers.SerializerMethodField()

    class Meta:
        model = Ride
        fields = [
            "id",
            "status",
            "vehicle_type",
            "pickup_address",
            "pickup_latitude",
            "pickup_longitude",
            "drop_address",
            "drop_latitude",
            "drop_longitude",
            "estimated_distance_km",
            "estimated_duration_minutes",
            "estimated_fare",
            "final_fare",
            "payment_method",
            "payment_status",
            "requested_at",
            "accepted_at",
            "arrived_at",
            "started_at",
            "completed_at",
            "cancelled_at",
            "cancellation_reason",
            "cancelled_by",
            "cancellation_note",
            "cancellation_fee",
            "cancellation_fee_status",
            "promo_code",
            "discount_amount",
            "payable_fare",
            "start_pin",
            "is_rated",
            "my_rating",
            "captain",
        ]
        read_only_fields = fields

    def get_start_pin(self, ride):
        return ride.start_pin if ride.status in PIN_VISIBLE else None

    def _rating(self, ride):
        try:
            return ride.rating
        except Ride.rating.RelatedObjectDoesNotExist:
            return None

    def get_is_rated(self, ride):
        return self._rating(ride) is not None

    def get_my_rating(self, ride):
        rating = self._rating(ride)
        return None if rating is None else {"rating": rating.rating, "comment": rating.comment}

    def get_captain(self, ride):
        if ride.captain_id is None:
            return None
        captain = ride.captain
        return {
            "name": captain.user.first_name or "Your captain",
            "rating": captain.rating,
            "total_rides": captain.total_rides,
        }


_CUSTOMER_ONLY = {"start_pin", "is_rated", "my_rating", "promo_code"}


class CaptainRideSerializer(RideSerializer):
    """The captain's view. Never includes the start PIN: the rider tells it to the captain."""

    customer_name = serializers.SerializerMethodField()
    start_pin = None
    is_rated = None
    my_rating = None

    class Meta(RideSerializer.Meta):
        fields = [f for f in RideSerializer.Meta.fields if f not in _CUSTOMER_ONLY] + [
            "start_pin_attempts",
            "customer_name",
            "is_platform_ride",
            "share_reason",
            "platform_share_amount",
        ]
        read_only_fields = fields

    def get_customer_name(self, ride):
        return ride.customer.first_name or "Customer"


class OfferSerializer(serializers.ModelSerializer):
    ride_id = serializers.UUIDField(source="ride.id", read_only=True)
    pickup_address = serializers.CharField(source="ride.pickup_address", read_only=True)
    drop_address = serializers.CharField(source="ride.drop_address", read_only=True)
    fare = serializers.DecimalField(source="ride.estimated_fare", max_digits=10, decimal_places=2, read_only=True)
    vehicle_type = serializers.CharField(source="ride.vehicle_type", read_only=True)

    class Meta:
        model = RideOffer
        fields = [
            "ride_id",
            "sequence",
            "distance_km",
            "expires_at",
            "pickup_address",
            "drop_address",
            "fare",
            "vehicle_type",
        ]
        read_only_fields = fields
