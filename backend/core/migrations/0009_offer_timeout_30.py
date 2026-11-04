from django.db import migrations, models


def raise_default_offer_timeout(apps, schema_editor):
    # The captain's acceptance window is 30 seconds. Only the old default is changed; an admin's own value stays.
    PlatformConfig = apps.get_model("core", "PlatformConfig")
    PlatformConfig.objects.filter(offer_timeout_seconds=15).update(offer_timeout_seconds=30)


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0008_seed_quick_places"),
    ]

    operations = [
        migrations.AlterField(
            model_name="platformconfig",
            name="offer_timeout_seconds",
            field=models.PositiveIntegerField(default=30, verbose_name="offer timeout (seconds)"),
        ),
        migrations.RunPython(raise_default_offer_timeout, migrations.RunPython.noop),
    ]
