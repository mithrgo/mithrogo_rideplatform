from decimal import Decimal

from django.db import migrations


# Migration 0007 gave every vehicle the Bike rate; Auto gets its own higher rate again.
def apply_rates(apps, schema_editor):
    FareConfig = apps.get_model("rides", "FareConfig")
    FareConfig.objects.filter(vehicle_type="AUTO").update(
        base_fare=Decimal("0.00"),
        per_km=Decimal("12.00"),
        minimum_fare=Decimal("50.00"),
        long_distance_after_km=None,
        long_distance_per_km=None,
    )


class Migration(migrations.Migration):
    dependencies = [("rides", "0008_restore_base_fare_help")]

    operations = [migrations.RunPython(apply_rates, migrations.RunPython.noop)]
