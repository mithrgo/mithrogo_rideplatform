import '../../../core/location/lat_lng.dart';
import '../../../core/utils/json.dart';
import 'ride.dart';
import 'ride_options.dart';

/// Matches services.tracking() in the backend. Polled while a ride is active.
class RideTracking {
  const RideTracking({
    required this.rideId,
    required this.status,
    required this.pickup,
    required this.drop,
    this.captain,
    this.startPin,
  });

  factory RideTracking.fromJson(Map<String, dynamic> json) {
    final pickup = json['pickup'] as Map<String, dynamic>;
    final drop = json['drop'] as Map<String, dynamic>;
    final captain = json['captain'] as Map<String, dynamic>?;
    return RideTracking(
      rideId: json['ride_id'] as String,
      status: RideStatus.fromApi(json['status'] as String? ?? ''),
      pickup: _place(pickup),
      drop: _place(drop),
      captain: captain == null ? null : CaptainInfo.fromJson(captain),
      startPin: json['start_pin'] as String?,
    );
  }

  final String rideId;
  final RideStatus status;
  final RidePoint pickup;
  final RidePoint drop;
  final CaptainInfo? captain;

  /// The rider's 4-digit start PIN. The backend sends it only from acceptance until the trip starts.
  final String? startPin;

  static RidePoint _place(Map<String, dynamic> json) {
    return RidePoint(
      address: json['address'] as String? ?? '',
      location: LatLng(
        latitude: parseDouble(json['latitude']),
        longitude: parseDouble(json['longitude']),
      ),
    );
  }
}

class RidePoint {
  const RidePoint({required this.address, required this.location});

  final String address;
  final LatLng location;
}

class CaptainInfo {
  const CaptainInfo({
    required this.name,
    this.rating,
    this.location,
    this.vehicle,
  });

  factory CaptainInfo.fromJson(Map<String, dynamic> json) {
    final lat = parseDoubleOrNull(json['latitude']);
    final lng = parseDoubleOrNull(json['longitude']);
    final vehicle = json['vehicle'] as Map<String, dynamic>?;
    return CaptainInfo(
      name: json['name'] as String? ?? 'Your captain',
      rating: parseDoubleOrNull(json['rating']),
      location: (lat == null || lng == null) ? null : LatLng(latitude: lat, longitude: lng),
      vehicle: vehicle == null ? null : CaptainVehicle.fromJson(vehicle),
    );
  }

  final String name;
  final double? rating;
  final LatLng? location;
  final CaptainVehicle? vehicle;
}

class CaptainVehicle {
  const CaptainVehicle({
    required this.type,
    required this.registrationNumber,
    this.make = '',
    this.model = '',
    this.color = '',
  });

  factory CaptainVehicle.fromJson(Map<String, dynamic> json) {
    return CaptainVehicle(
      type: VehicleType.fromApi(json['type'] as String? ?? ''),
      registrationNumber: json['registration_number'] as String? ?? '',
      make: json['make'] as String? ?? '',
      model: json['model'] as String? ?? '',
      color: json['color'] as String? ?? '',
    );
  }

  final VehicleType type;
  final String registrationNumber;
  final String make;
  final String model;
  final String color;

  /// "White Honda Activa" style line, skipping blank parts.
  String get description => [color, make, model].where((part) => part.isNotEmpty).join(' ');
}
