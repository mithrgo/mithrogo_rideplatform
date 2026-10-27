from rest_framework import serializers

from core.models import AuditLog, PlatformConfig, QuickPlace
from apps.captains.models import CaptainProfile, KycDocument
from apps.payments.models import Payment
from apps.promotions.models import PromoCode
from apps.rides.models import FareConfig, Ride, RideEvent, RideLocation, RideOffer
from apps.subscriptions.models import CaptainSubscription, PlatformDue, SubscriptionPlan
from apps.support.models import SosAlert, SupportTicket, TicketMessage
from apps.users.models import User
from apps.vehicles.models import Vehicle


class UserBriefSerializer(serializers.ModelSerializer):
    name = serializers.CharField(source="full_name", read_only=True)

    class Meta:
        model = User
        fields = ["id", "phone", "name", "role", "is_active"]
        read_only_fields = fields


class CustomerSerializer(serializers.ModelSerializer):
    name = serializers.CharField(source="full_name", read_only=True)
    total_rides = serializers.IntegerField(read_only=True)
    completed_rides = serializers.IntegerField(read_only=True)
    emergency_contact_name = serializers.CharField(source="customer_profile.emergency_contact_name", read_only=True)
    emergency_contact_phone = serializers.CharField(source="customer_profile.emergency_contact_phone", read_only=True)
    referral_code = serializers.CharField(source="customer_profile.referral_code", read_only=True)

    class Meta:
        model = User
        fields = [
            "id", "phone", "name", "first_name", "last_name", "email", "is_active", "deleted_at",
            "total_rides", "completed_rides", "emergency_contact_name", "emergency_contact_phone",
            "referral_code", "created_at",
        ]
        read_only_fields = fields


class VehicleSerializer(serializers.ModelSerializer):
    class Meta:
        model = Vehicle
        fields = ["id", "vehicle_type", "registration_number", "make", "model", "color", "is_verified", "verified_at"]
        read_only_fields = fields


class KycDocumentSerializer(serializers.ModelSerializer):
    file_url = serializers.SerializerMethodField()

    class Meta:
        model = KycDocument
        fields = ["id", "doc_type", "file_url", "created_at"]
        read_only_fields = fields

    def get_file_url(self, doc):
        request = self.context.get("request")
        url = doc.file.url if doc.file else ""
        return request.build_absolute_uri(url) if request and url else url


class CaptainSerializer(serializers.ModelSerializer):
    user = UserBriefSerializer(read_only=True)

    class Meta:
        model = CaptainProfile
        fields = [
            "id", "user", "kyc_status", "kyc_rejection_reason", "online_status", "rating", "total_rides",
            "cancelled_rides", "license_number", "license_expiry", "day_vehicle_type", "current_latitude",
            "current_longitude", "last_location_at", "created_at",
        ]
        read_only_fields = fields


class CaptainDetailSerializer(CaptainSerializer):
    vehicles = VehicleSerializer(many=True, read_only=True)
    documents = KycDocumentSerializer(source="kyc_documents", many=True, read_only=True)

    class Meta(CaptainSerializer.Meta):
        fields = CaptainSerializer.Meta.fields + ["date_of_birth", "address", "vehicles", "documents"]
        read_only_fields = fields


class RideListSerializer(serializers.ModelSerializer):
    customer = UserBriefSerializer(read_only=True)
    captain_name = serializers.SerializerMethodField()
    captain_phone = serializers.SerializerMethodField()
    payable_fare = serializers.DecimalField(max_digits=10, decimal_places=2, read_only=True)

    class Meta:
        model = Ride
        fields = [
            "id", "status", "vehicle_type", "customer", "captain_id", "captain_name", "captain_phone",
            "pickup_address", "pickup_latitude", "pickup_longitude", "drop_address", "drop_latitude",
            "drop_longitude", "estimated_distance_km", "estimated_fare", "final_fare", "discount_amount",
            "payable_fare", "promo_code", "payment_method", "payment_status", "cancelled_by",
            "cancellation_reason", "cancellation_fee", "cancellation_fee_status", "is_platform_ride",
            "requested_at", "accepted_at", "arrived_at", "started_at", "completed_at", "cancelled_at",
        ]
        read_only_fields = fields

    def get_captain_name(self, ride):
        return ride.captain.user.full_name if ride.captain_id else None

    def get_captain_phone(self, ride):
        return ride.captain.user.phone if ride.captain_id else None


class RideEventSerializer(serializers.ModelSerializer):
    actor = UserBriefSerializer(read_only=True)

    class Meta:
        model = RideEvent
        fields = ["id", "from_status", "to_status", "actor", "note", "created_at"]
        read_only_fields = fields


class RideLocationSerializer(serializers.ModelSerializer):
    class Meta:
        model = RideLocation
        fields = ["latitude", "longitude", "heading", "speed", "recorded_at"]
        read_only_fields = fields


class RideOfferSerializer(serializers.ModelSerializer):
    captain_phone = serializers.CharField(source="captain.user.phone", read_only=True)

    class Meta:
        model = RideOffer
        fields = ["id", "sequence", "captain_id", "captain_phone", "distance_km", "status", "expires_at",
                  "responded_at", "created_at"]
        read_only_fields = fields


class RideDetailSerializer(RideListSerializer):
    events = RideEventSerializer(many=True, read_only=True)
    offers = RideOfferSerializer(many=True, read_only=True)
    rating = serializers.SerializerMethodField()

    class Meta(RideListSerializer.Meta):
        fields = RideListSerializer.Meta.fields + [
            "estimated_duration_minutes", "cancellation_note", "start_pin_attempts", "share_reason",
            "platform_share_amount", "events", "offers", "rating",
        ]
        read_only_fields = fields

    def get_rating(self, ride):
        try:
            rating = ride.rating
        except Ride.rating.RelatedObjectDoesNotExist:
            return None
        return {"rating": rating.rating, "comment": rating.comment}


class PaymentSerializer(serializers.ModelSerializer):
    user = UserBriefSerializer(read_only=True)

    class Meta:
        model = Payment
        fields = ["id", "user", "payment_type", "amount", "currency", "provider", "provider_order_id",
                  "provider_payment_id", "status", "metadata", "created_at", "updated_at"]
        read_only_fields = fields


class SubscriptionSerializer(serializers.ModelSerializer):
    captain_phone = serializers.CharField(source="captain.user.phone", read_only=True)
    plan_code = serializers.CharField(source="plan.code", read_only=True)
    plan_name = serializers.CharField(source="plan.name", read_only=True)
    amount = serializers.DecimalField(source="plan.amount", max_digits=10, decimal_places=2, read_only=True)

    class Meta:
        model = CaptainSubscription
        fields = ["id", "captain_id", "captain_phone", "plan_code", "plan_name", "amount", "status", "start_at",
                  "expires_at", "penalty_pending", "created_at"]
        read_only_fields = fields


class DueSerializer(serializers.ModelSerializer):
    captain_phone = serializers.CharField(source="captain.user.phone", read_only=True)

    class Meta:
        model = PlatformDue
        fields = ["id", "captain_id", "captain_phone", "ride_id", "due_type", "amount", "status", "created_at",
                  "settled_at"]
        read_only_fields = fields


class TicketMessageSerializer(serializers.ModelSerializer):
    author = UserBriefSerializer(read_only=True)

    class Meta:
        model = TicketMessage
        fields = ["id", "is_staff", "author", "body", "created_at"]
        read_only_fields = fields


class TicketSerializer(serializers.ModelSerializer):
    user = UserBriefSerializer(read_only=True)
    is_sos = serializers.SerializerMethodField()

    class Meta:
        model = SupportTicket
        fields = ["id", "user", "category", "ride_id", "description", "status", "resolution_note", "is_sos",
                  "created_at", "updated_at"]
        read_only_fields = fields

    def get_is_sos(self, ticket):
        return hasattr(ticket, "sos")


class TicketDetailSerializer(TicketSerializer):
    messages = TicketMessageSerializer(many=True, read_only=True)

    class Meta(TicketSerializer.Meta):
        fields = TicketSerializer.Meta.fields + ["messages"]
        read_only_fields = fields


class SosSerializer(serializers.ModelSerializer):
    user = UserBriefSerializer(read_only=True)
    handled_by = UserBriefSerializer(read_only=True)
    ride_status = serializers.CharField(source="ride.status", read_only=True, default=None)

    class Meta:
        model = SosAlert
        fields = ["id", "user", "ride_id", "ride_status", "ticket_id", "latitude", "longitude", "note", "status",
                  "handled_by", "acknowledged_at", "resolved_at", "resolution_note", "created_at"]
        read_only_fields = fields


class PromoCodeSerializer(serializers.ModelSerializer):
    times_used = serializers.IntegerField(read_only=True)

    class Meta:
        model = PromoCode
        fields = ["id", "code", "description", "discount_type", "value", "max_discount", "min_fare", "valid_from",
                  "valid_until", "max_uses_total", "max_uses_per_user", "first_ride_only", "assigned_user",
                  "is_active", "times_used", "created_at"]
        read_only_fields = ["id", "assigned_user", "times_used", "created_at"]

    def validate(self, attrs):
        kind = attrs.get("discount_type", getattr(self.instance, "discount_type", None))
        value = attrs.get("value", getattr(self.instance, "value", None))
        if value is not None and value <= 0:
            raise serializers.ValidationError({"value": "Must be more than 0."})
        if kind == "PERCENT" and value is not None and value > 100:
            raise serializers.ValidationError({"value": "A percentage cannot be more than 100."})
        return attrs


class FareConfigSerializer(serializers.ModelSerializer):
    class Meta:
        model = FareConfig
        fields = ["id", "vehicle_type", "base_fare", "per_km", "minimum_fare", "long_distance_after_km",
                  "long_distance_per_km", "platform_customer_fee", "is_active",
                  "updated_at"]
        read_only_fields = ["id", "vehicle_type", "updated_at"]


class PlanSerializer(serializers.ModelSerializer):
    class Meta:
        model = SubscriptionPlan
        fields = ["id", "code", "name", "plan_type", "amount", "duration_hours", "vehicle_type", "qualifying_rides",
                  "shortfall_fee", "is_active", "updated_at"]
        read_only_fields = ["id", "code", "plan_type", "vehicle_type", "updated_at"]


class PlatformConfigSerializer(serializers.ModelSerializer):
    class Meta:
        model = PlatformConfig
        exclude = ["id", "created_at"]
        read_only_fields = ["updated_at"]


class AuditLogSerializer(serializers.ModelSerializer):
    actor = UserBriefSerializer(read_only=True)

    class Meta:
        model = AuditLog
        fields = ["id", "actor", "action", "model", "object_id", "changes", "created_at"]
        read_only_fields = fields


class QuickPlaceSerializer(serializers.ModelSerializer):
    latitude = serializers.DecimalField(max_digits=9, decimal_places=6, min_value=-90, max_value=90)
    longitude = serializers.DecimalField(max_digits=9, decimal_places=6, min_value=-180, max_value=180)

    class Meta:
        model = QuickPlace
        fields = ["id", "name", "address", "latitude", "longitude", "icon", "sort_order", "is_active", "updated_at"]
        read_only_fields = ["id", "updated_at"]
