import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationException implements Exception {
  const LocationException(this.message);

  /// Safe to show to the captain.
  final String message;

  @override
  String toString() => 'LocationException: $message';
}

/// Reads the device GPS. Only foreground ("while in use") permission is requested.
class LocationService {
  static const _timeout = Duration(seconds: 15);

  Future<Position> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('Turn on location services to receive ride requests.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException('Location access is blocked. Allow it in settings to go online.');
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('Allow location access to go online.');
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: _timeout),
      );
    } on TimeoutException {
      throw const LocationException('Could not get your location. Move to an open area and try again.');
    }
  }
}
