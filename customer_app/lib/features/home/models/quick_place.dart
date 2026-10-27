import '../../../core/location/place.dart';

/// A popular destination card. The list, order and coordinates all come from the admin console.
class QuickPlace {
  const QuickPlace({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.icon,
  });

  final String name;
  final String address;
  final double latitude;
  final double longitude;

  /// A key such as `train` or `hospital`. The widget maps it to an icon; unknown keys get a pin.
  final String icon;

  /// Null when the data is damaged, so one bad row never hides the others.
  static QuickPlace? tryFromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = json['name'];
    final address = json['address'];
    final latitude = double.tryParse('${json['latitude']}');
    final longitude = double.tryParse('${json['longitude']}');
    if (name is! String || address is! String || latitude == null || longitude == null) return null;
    return QuickPlace(
      name: name,
      address: address,
      latitude: latitude,
      longitude: longitude,
      icon: json['icon'] is String ? json['icon'] as String : 'place',
    );
  }

  Place toPlace() => Place(name: name, address: address, latitude: latitude, longitude: longitude);
}
