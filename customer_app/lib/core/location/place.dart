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

  /// For saving a place on the device. [distanceMeters] is left out: it belongs to one search.
  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'subtitle': subtitle,
        'id': id,
      };

  /// Null when the saved data is damaged, so one bad entry never breaks the list.
  static Place? tryFromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = json['name'];
    final address = json['address'];
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    if (name is! String || address is! String || latitude is! num || longitude is! num) return null;
    final place = Place(
      name: name,
      address: address,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      subtitle: json['subtitle'] is String ? json['subtitle'] as String : '',
      id: json['id'] is String ? json['id'] as String : null,
    );
    return place.latLng.isValid ? place : null;
  }
}
