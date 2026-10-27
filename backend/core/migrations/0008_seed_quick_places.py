from django.db import migrations

# Starting rows only. Admins add, edit, reorder and hide these from the admin console.
# Coordinates were checked against OpenStreetMap.
PLACES = [
    ("Railway Station", "train", "18.678787", "78.103517", "Nizamabad Junction, Nizamabad, Telangana"),
    ("Bus Stand", "bus", "18.676072", "78.099539", "TGSRTC Bus Station, Nizamabad, Telangana"),
    ("Venu Mall", "mall", "18.669175", "78.105444", "Venu Mall, Santhosh Reddy Road, Nizamabad, Telangana"),
    ("Government Hospital", "hospital", "18.675625", "78.098850", "Government General Hospital, Nizamabad, Telangana"),
    ("Medical College", "hospital", "18.672695", "78.099500", "Government Medical College Hospital, Nizamabad, Telangana"),
    ("Kanteshwar Temple", "temple", "18.685783", "78.114403", "Kanteshwar Temple, Nizamabad, Telangana"),
]


def seed(apps, schema_editor):
    QuickPlace = apps.get_model("core", "QuickPlace")
    if QuickPlace.objects.exists():
        return
    for order, (name, icon, lat, lng, address) in enumerate(PLACES, start=1):
        QuickPlace.objects.create(
            name=name, icon=icon, latitude=lat, longitude=lng, address=address, sort_order=order
        )


class Migration(migrations.Migration):
    dependencies = [("core", "0007_platformconfig_search_timeout")]

    operations = [migrations.RunPython(seed, migrations.RunPython.noop)]
