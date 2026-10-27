import math

EARTH_RADIUS_KM = 6371.0088


def haversine_km(lat1, lon1, lat2, lon2):
    """Great-circle distance in km between two points (numbers or Decimals)."""
    lat1, lon1, lat2, lon2 = (math.radians(float(v)) for v in (lat1, lon1, lat2, lon2))
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * EARTH_RADIUS_KM * math.asin(math.sqrt(a))


def parse_polygon(text):
    """Parse one 'latitude, longitude' pair per line into [(lat, lon), ...]. Raises ValueError if malformed."""
    points = []
    for number, line in enumerate((text or "").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            lat, lon = (float(part) for part in line.split(","))
        except ValueError:
            raise ValueError(f"Line {number}: write it as 'latitude, longitude', for example 18.6725, 78.0941.")
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            raise ValueError(f"Line {number}: latitude must be -90..90 and longitude -180..180.")
        points.append((lat, lon))
    if len(points) < 3:
        raise ValueError("A polygon needs at least 3 points.")
    return points


def point_in_polygon(lat, lon, points):
    """Ray casting: True if the point is inside the polygon. Fine for city-sized areas."""
    lat, lon = float(lat), float(lon)
    inside = False
    j = len(points) - 1
    for i, (lat_i, lon_i) in enumerate(points):
        lat_j, lon_j = points[j]
        if (lon_i > lon) != (lon_j > lon) and lat < (lat_j - lat_i) * (lon - lon_i) / (lon_j - lon_i) + lat_i:
            inside = not inside
        j = i
    return inside
