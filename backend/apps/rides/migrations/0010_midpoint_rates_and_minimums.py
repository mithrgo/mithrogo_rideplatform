from decimal import Decimal

from django.db import migrations


# Bike Rs 9/km (range 8-10), Auto Rs 16.50/km (range 15-18); minimum fares Rs 22 and Rs 53. No base fare or tiering.
RATES = {"BIKE": ("9.00", "22.00"), "AUTO": ("16.50", "53.00")}


def apply_rates(apps, schema_editor):
    FareConfig = apps.get_model("rides", "FareConfig")
    for vehicle_type, (per_km, minimum_fare) in RATES.items():
        FareConfig.objects.filter(vehicle_type=vehicle_type).update(
            base_fare=Decimal("0.00"),
            per_km=Decimal(per_km),
            minimum_fare=Decimal(minimum_fare),
            long_distance_after_km=None,
            long_distance_per_km=None,
        )


class Migration(migrations.Migration):
    dependencies = [("rides", "0009_auto_own_rate")]

    operations = [migrations.RunPython(apply_rates, migrations.RunPython.noop)]
