import 'dart:math' as math;

class LatLng {
  const LatLng({required this.latitude, required this.longitude});

  /// Latitude first, longitude second. OSRM is the one API that wants longitude first.
  final double latitude;
  final double longitude;

  /// False for out-of-range values and for (0, 0), which is what an unset or failed GPS fix often looks like.
  bool get isValid {
    if (latitude.isNaN || longitude.isNaN) return false;
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return false;
    return !(latitude == 0 && longitude == 0);
  }

  /// Great-circle distance in metres.
  double distanceTo(LatLng other) {
    const earthRadius = 6371000.0;
    double rad(double deg) => deg * math.pi / 180;
    final dLat = rad(other.latitude - latitude);
    final dLng = rad(other.longitude - longitude);
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final a = sinLat * sinLat +
        math.cos(rad(latitude)) * math.cos(rad(other.latitude)) * sinLng * sinLng;
    return 2 * earthRadius * math.asin(math.min(1.0, math.sqrt(a)));
  }

  // Value equality, so map and route providers can tell when a point really changed.
  @override
  bool operator ==(Object other) =>
      other is LatLng && other.latitude == latitude && other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'LatLng($latitude, $longitude)';
}
