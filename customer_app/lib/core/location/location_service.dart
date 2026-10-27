import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'lat_lng.dart';
import 'service_area.dart';

/// Where the rider is. The device GPS is read through [GeolocatorLocationService].
abstract class LocationService {
  /// Throws [LocationException] when the position cannot be read or cannot be trusted.
  Future<LatLng> currentLocation();
}

enum LocationFailure {
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  outsideServiceArea,
  unavailable,
}

class LocationException implements Exception {
  const LocationException(this.failure, this.message);

  final LocationFailure failure;

  /// Safe to show to the rider.
  final String message;

  /// Whether the rider can fix this in the phone's settings.
  bool get needsSettings =>
      failure == LocationFailure.servicesDisabled || failure == LocationFailure.permissionDeniedForever;

  @override
  String toString() => 'LocationException($failure): $message';
}

/// Reads the real device position. Only foreground ("while in use") permission is requested.
class GeolocatorLocationService implements LocationService {
  static const _timeout = Duration(seconds: 15);

  /// A fix this recent is reused, so opening search does not wait for a new GPS reading.
  static const _recentFix = Duration(seconds: 60);

  @override
  Future<LatLng> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
        LocationFailure.servicesDisabled,
        'Turn on location services to find your pickup point.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        LocationFailure.permissionDeniedForever,
        'Location access is blocked. Allow it in settings to use your current location.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException(
        LocationFailure.permissionDenied,
        'Allow location access to use your current location, or choose a pickup point.',
      );
    }

    final LatLng point;
    try {
      final last = await Geolocator.getLastKnownPosition();
      final isRecent = last != null && DateTime.now().difference(last.timestamp) <= _recentFix;
      final position = isRecent ? last : await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _timeout,
        ),
      );
      point = LatLng(latitude: position.latitude, longitude: position.longitude);
    } on TimeoutException {
      throw const LocationException(
        LocationFailure.unavailable,
        'Could not get your location in time. Try again, or choose a pickup point.',
      );
    } catch (_) {
      throw const LocationException(
        LocationFailure.unavailable,
        'Could not get your location. Try again, or choose a pickup point.',
      );
    }

    if (!point.isValid) {
      throw const LocationException(
        LocationFailure.unavailable,
        'Your device returned an invalid location. Try again, or choose a pickup point.',
      );
    }
    if (!isInServiceArea(point)) {
      throw const LocationException(
        LocationFailure.outsideServiceArea,
        'Your device location is outside India. Choose a pickup point to continue.',
      );
    }
    return point;
  }
}
