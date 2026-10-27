import 'lat_lng.dart';

/// A pickup or drop point. [address] is what the backend stores on the ride (max 255 characters).
/// [subtitle] is only for display, e.g. "Station Road · Telangana · 940 m away".
///
/// [id] is the stable OpenStreetMap identity ("node:123") when the source gives one.
/// [distanceMeters] is set by search, measured from the search origin.
class Place {
  const Place({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.subtitle = '',
    this.id,
    this.distanceMeters,
  });

  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String subtitle;
  final String? id;
  final double? distanceMeters;

  LatLng get latLng => LatLng(latitude: latitude, longitude: longitude);
}
