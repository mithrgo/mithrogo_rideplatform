"""Destination search limited to the backend search radius around the rider's GPS position.

The app sends its position. Nominatim is asked only for places inside a box around that position,
then every result outside PlatformConfig.search_radius_km is dropped and the rest are ordered by
distance. Nothing outside the radius is returned, and there is no wider fallback.
"""

import hashlib
import json
import math
import urllib.error
import urllib.parse
import urllib.request

from django.conf import settings
from django.core.cache import cache

from core.geo import haversine_km
from core.models import PlatformConfig

MAX_RESULTS = 20
CACHE_SECONDS = 600
REQUEST_TIMEOUT_SECONDS = 8
METRES_PER_DEGREE_LAT = 111320.0
# The box is a little wider than the radius, so the distance check below decides what is kept.
BOX_MARGIN = 1.25
_LOCALITY_KEYS = ("neighbourhood", "suburb", "quarter", "village", "town", "city_district", "city", "county")


class PlaceSearchUnavailable(Exception):
    """Nominatim could not be reached or returned something unreadable."""


def search_nearby(query, latitude, longitude):
    """Places matching [query] within the configured radius of the point, nearest first."""
    radius_km = float(PlatformConfig.load().search_radius_km)
    key = _cache_key(query, latitude, longitude, radius_km)
    results = cache.get(key)
    if results is None:
        raw = _fetch(query, latitude, longitude, radius_km)
        results = _within_radius(raw, latitude, longitude, radius_km)
        cache.set(key, results, CACHE_SECONDS)
    return {"radius_km": radius_km, "results": results}


def _cache_key(query, latitude, longitude, radius_km):
    # Coordinates are rounded to about 10 m, so a GPS fix that barely moved reuses the same answer.
    raw = f"{query.strip().lower()}|{latitude:.4f}|{longitude:.4f}|{radius_km}"
    return "place-search:" + hashlib.sha256(raw.encode()).hexdigest()


def search_box(latitude, longitude, radius_km):
    """Nominatim viewbox `left,top,right,bottom` (min lon, max lat, max lon, min lat) around the point."""
    d_lat = radius_km * 1000 * BOX_MARGIN / METRES_PER_DEGREE_LAT
    d_lng = d_lat / math.cos(math.radians(latitude))
    return ",".join(
        f"{value:.6f}"
        for value in (longitude - d_lng, latitude + d_lat, longitude + d_lng, latitude - d_lat)
    )


def _fetch(query, latitude, longitude, radius_km):
    params = {
        "q": query.strip(),
        "format": "jsonv2",
        "addressdetails": "1",
        "limit": "40",
        "countrycodes": "in",
        "bounded": "1",
        "viewbox": search_box(latitude, longitude, radius_km),
        "accept-language": "en",
    }
    url = f"{settings.NOMINATIM_BASE_URL.rstrip('/')}/search?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"User-Agent": settings.NOMINATIM_USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            body = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
        raise PlaceSearchUnavailable(str(exc)) from exc
    if not isinstance(body, list):
        raise PlaceSearchUnavailable("unexpected response")
    return body


def _within_radius(items, latitude, longitude, radius_km):
    """Keep only places inside the radius, nearest first, without duplicates."""
    places = []
    seen = set()
    for item in items:
        place = _place_from(item, latitude, longitude)
        if place is None or place["distance_km"] > radius_km:
            continue
        if place["id"] in seen:
            continue
        seen.add(place["id"])
        places.append(place)
    places.sort(key=lambda place: place["distance_km"])
    return places[:MAX_RESULTS]


def _place_from(item, latitude, longitude):
    if not isinstance(item, dict):
        return None
    try:
        place_lat = float(item["lat"])
        place_lng = float(item["lon"])
    except (KeyError, TypeError, ValueError):
        return None
    address = item.get("address") if isinstance(item.get("address"), dict) else {}
    if str(address.get("country_code", "in")).lower() != "in":
        return None

    display_name = _text(item.get("display_name"))
    name = _text(item.get("name")) or (display_name.split(",")[0].strip() if display_name else "")
    if not name:
        return None

    osm_type, osm_id = _text(item.get("osm_type")), item.get("osm_id")
    locality = next((_text(address.get(key)) for key in _LOCALITY_KEYS if _text(address.get(key)) not in (None, name)), None)
    return {
        "id": f"{osm_type}:{osm_id}" if osm_type and osm_id is not None else f"{name}@{place_lat:.5f},{place_lng:.5f}",
        "name": name,
        "address": (display_name or name)[:255],
        "latitude": round(place_lat, 6),
        "longitude": round(place_lng, 6),
        "distance_km": round(haversine_km(latitude, longitude, place_lat, place_lng), 2),
        "locality": locality,
        "state": _text(address.get("state")),
    }


def _text(value):
    if not isinstance(value, str):
        return None
    value = value.strip()
    return value or None
