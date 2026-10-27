from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models

from core.geo import haversine_km, parse_polygon, point_in_polygon


class TimeStampedModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class PlatformConfig(TimeStampedModel):
    """Single row of operational settings. Edit in admin; never hard-code these values."""

    search_radius_km = models.DecimalField("search radius (km)", max_digits=5, decimal_places=2, default=3)
    offer_timeout_seconds = models.PositiveIntegerField("offer timeout (seconds)", default=15)
    search_timeout_seconds = models.PositiveIntegerField("search timeout (seconds)", default=120)
    max_offer_attempts = models.PositiveIntegerField("max captains offered per ride", default=5)
    location_freshness_seconds = models.PositiveIntegerField(
        "captain location freshness (seconds)",
        default=30,
        help_text="A captain whose last location is older than this is not matched.",
    )
    road_distance_factor = models.DecimalField(
        "road distance factor",
        max_digits=4,
        decimal_places=2,
        default="1.30",
        help_text="Straight-line distance is multiplied by this to estimate road distance.",
    )
    average_speed_kmph = models.DecimalField("average speed (km/h)", max_digits=5, decimal_places=2, default=20)
    min_trip_km = models.DecimalField("minimum trip distance (km)", max_digits=5, decimal_places=2, default="0.50")
    unpaid_dues_limit = models.DecimalField(
        "unpaid dues limit (₹)",
        max_digits=10,
        decimal_places=2,
        default=500,
        help_text="Captains whose pending platform dues exceed this cannot go online.",
    )
    service_timezone = models.CharField(
        "service timezone",
        max_length=64,
        default=settings.TIME_ZONE,
        help_text="Defines the business day for ride-share counting.",
    )

    # Service area
    restrict_to_service_area = models.BooleanField(
        "restrict rides to the service area",
        default=True,
        help_text="Pickup, drop and the rider's own device must all be inside the service area to book.",
    )
    service_area_name = models.CharField("service area name", max_length=60, default="Nizamabad")
    service_area_latitude = models.DecimalField(
        "service area centre latitude", max_digits=9, decimal_places=6, default="18.672500"
    )
    service_area_longitude = models.DecimalField(
        "service area centre longitude", max_digits=9, decimal_places=6, default="78.094100"
    )
    service_area_radius_km = models.DecimalField(
        "service area radius (km)", max_digits=5, decimal_places=2, default=20
    )

    # Ride safety
    require_start_pin = models.BooleanField(
        "require ride start PIN",
        default=True,
        help_text="The captain must enter the rider's 4-digit PIN to start the ride.",
    )
    start_pin_max_attempts = models.PositiveSmallIntegerField("wrong PIN attempts allowed", default=5)

    # Cancellations
    customer_cancel_fee = models.DecimalField(
        "customer cancellation fee (₹)",
        max_digits=8,
        decimal_places=2,
        default=0,
        help_text="Charged when the rider cancels after the free window. 0 turns the fee off.",
    )
    cancel_free_window_seconds = models.PositiveIntegerField(
        "free cancellation window (seconds)",
        default=120,
        help_text="Time after a captain accepts during which the rider can cancel for free.",
    )
    customer_no_show_fee = models.DecimalField(
        "rider no-show fee (₹)",
        max_digits=8,
        decimal_places=2,
        default=0,
        help_text="Charged when the captain cancels because the rider never came. 0 turns the fee off.",
    )
    no_show_wait_minutes = models.PositiveIntegerField(
        "no-show wait (minutes)",
        default=5,
        help_text="How long a captain must wait at pickup before cancelling for a no-show.",
    )
    block_booking_on_unpaid_fees = models.BooleanField(
        "block booking while fees are unpaid",
        default=True,
        help_text="Riders must pay outstanding cancellation fees before booking again.",
    )

    # Referrals
    referral_referee_reward = models.DecimalField(
        "referral reward for the new rider (₹)",
        max_digits=8,
        decimal_places=2,
        default=0,
        help_text="Flat discount given to a rider who applies a referral code. 0 turns referrals off.",
    )
    referral_referrer_reward = models.DecimalField(
        "referral reward for the referrer (₹)",
        max_digits=8,
        decimal_places=2,
        default=0,
        help_text="Flat discount given to the referrer after the new rider completes a first ride.",
    )
    referral_reward_valid_days = models.PositiveIntegerField("referral reward validity (days)", default=30)

    # Notifications and sharing
    plan_expiry_reminder_minutes = models.PositiveIntegerField(
        "plan expiry reminder (minutes before)",
        default=60,
        help_text="Captains are reminded this long before a daily plan runs out.",
    )
    share_link_grace_minutes = models.PositiveIntegerField(
        "trip share link grace (minutes)",
        default=30,
        help_text="A shared trip link keeps working this long after the ride ends.",
    )

    class Meta:
        verbose_name = "platform configuration"
        verbose_name_plural = "platform configuration"

    def __str__(self):
        return "Platform configuration"

    def save(self, *args, **kwargs):
        self.pk = 1
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        pass  # the singleton cannot be deleted

    @classmethod
    def load(cls):
        """The live configuration row. Re-read so values are database types, not Python defaults."""
        cls.objects.get_or_create(pk=1)
        return cls.objects.get(pk=1)


class AuditLog(models.Model):
    """Who changed what in the admin, and when. Written by core.audit.record."""

    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="audit_logs",
    )
    action = models.CharField(max_length=80)
    model = models.CharField(max_length=80)
    object_id = models.CharField(max_length=64)
    changes = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.action} {self.model}#{self.object_id}"


class ServiceZone(TimeStampedModel):
    """An extra bookable area on top of the main service area, for example an airport or a nearby town."""

    class Shape(models.TextChoices):
        CIRCLE = "CIRCLE", "Circle (centre and radius)"
        POLYGON = "POLYGON", "Polygon (list of corner points)"

    name = models.CharField(max_length=80)
    shape = models.CharField(max_length=10, choices=Shape.choices, default=Shape.CIRCLE)
    latitude = models.DecimalField("centre latitude", max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField("centre longitude", max_digits=9, decimal_places=6, null=True, blank=True)
    radius_km = models.DecimalField("radius (km)", max_digits=5, decimal_places=2, null=True, blank=True)
    polygon_points = models.TextField(
        "corner points",
        blank=True,
        help_text="One 'latitude, longitude' pair per line, going around the edge of the area.",
    )
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name

    def clean(self):
        if self.shape == self.Shape.CIRCLE:
            if self.latitude is None or self.longitude is None or not self.radius_km:
                raise ValidationError("A circle needs a centre latitude, centre longitude and radius.")
        else:
            try:
                parse_polygon(self.polygon_points)
            except ValueError as exc:
                raise ValidationError({"polygon_points": str(exc)})

    def contains(self, latitude, longitude):
        if self.shape == self.Shape.CIRCLE:
            return haversine_km(latitude, longitude, self.latitude, self.longitude) <= float(self.radius_km)
        return point_in_polygon(latitude, longitude, parse_polygon(self.polygon_points))


class QuickPlace(TimeStampedModel):
    """A popular destination shown as a card on the customer app's home screen. Managed in admin."""

    class Icon(models.TextChoices):
        PLACE = "place", "Pin"
        TRAIN = "train", "Train"
        BUS = "bus", "Bus"
        MALL = "mall", "Shopping"
        HOSPITAL = "hospital", "Hospital"
        TEMPLE = "temple", "Temple"
        SCHOOL = "school", "School"
        AIRPORT = "airport", "Airport"
        RESTAURANT = "restaurant", "Food"
        PARK = "park", "Park"
        OFFICE = "office", "Office"

    name = models.CharField(max_length=40, help_text="Short label on the card, e.g. Railway Station.")
    address = models.CharField(max_length=255, help_text="Full address saved on the ride.")
    latitude = models.DecimalField(max_digits=9, decimal_places=6)
    longitude = models.DecimalField(max_digits=9, decimal_places=6)
    icon = models.CharField(max_length=12, choices=Icon.choices, default=Icon.PLACE)
    sort_order = models.PositiveSmallIntegerField(default=0, help_text="Smaller numbers show first.")
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["sort_order", "name"]

    def __str__(self):
        return self.name

    def clean(self):
        if self.latitude is not None and not -90 <= self.latitude <= 90:
            raise ValidationError({"latitude": "Latitude must be between -90 and 90."})
        if self.longitude is not None and not -180 <= self.longitude <= 180:
            raise ValidationError({"longitude": "Longitude must be between -180 and 180."})
