import '../../../core/utils/json.dart';

class Ride {
  const Ride({
    required this.id,
    required this.status,
    required this.vehicleType,
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropAddress,
    required this.dropLat,
    required this.dropLng,
    required this.distanceKm,
    required this.fare,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.customerName,
    required this.isPlatformRide,
    required this.completedAt,
    required this.requestedAt,
  });

  factory Ride.fromJson(Map<String, dynamic> json) {
    final finalFare = json['final_fare'];
    return Ride(
      id: json['id'].toString(),
      status: (json['status'] as String?) ?? '',
      vehicleType: (json['vehicle_type'] as String?) ?? '',
      pickupAddress: (json['pickup_address'] as String?) ?? '',
      pickupLat: parseDouble(json['pickup_latitude']),
      pickupLng: parseDouble(json['pickup_longitude']),
      dropAddress: (json['drop_address'] as String?) ?? '',
      dropLat: parseDouble(json['drop_latitude']),
      dropLng: parseDouble(json['drop_longitude']),
      distanceKm: parseDouble(json['estimated_distance_km']),
      fare: (finalFare ?? json['estimated_fare'])?.toString() ?? '0',
      paymentMethod: (json['payment_method'] as String?) ?? '',
      paymentStatus: (json['payment_status'] as String?) ?? '',
      customerName: (json['customer_name'] as String?) ?? 'Customer',
      isPlatformRide: json['is_platform_ride'] == true,
      completedAt: DateTime.tryParse((json['completed_at'] as String?) ?? ''),
      requestedAt: DateTime.tryParse((json['requested_at'] as String?) ?? ''),
    );
  }

  final String id;
  final String status;
  final String vehicleType;
  final String pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final String dropAddress;
  final double dropLat;
  final double dropLng;
  final double distanceKm;

  /// The final fare once the ride is done, the estimate before that.
  final String fare;
  final String paymentMethod;
  final String paymentStatus;
  final String customerName;
  final bool isPlatformRide;
  final DateTime? completedAt;
  final DateTime? requestedAt;

  bool get isActive => status == 'ACCEPTED' || status == 'CAPTAIN_ARRIVED' || status == 'STARTED';

  bool get isCash => paymentMethod == 'CASH';

  String get statusLabel => switch (status) {
        'ACCEPTED' => 'Head to pickup',
        'CAPTAIN_ARRIVED' => 'Waiting for rider',
        'STARTED' => 'Ride in progress',
        'COMPLETED' => 'Completed',
        'CANCELLED' => 'Cancelled',
        _ => status,
      };
}

/// Reasons a captain can give when cancelling before the ride starts (backend CaptainCancelReason).
const captainCancelReasons = <String, String>{
  'CUSTOMER_NOT_AT_PICKUP': 'Rider did not come to pickup',
  'CUSTOMER_ASKED': 'Rider asked me to cancel',
  'VEHICLE_ISSUE': 'Vehicle problem',
  'PICKUP_UNREACHABLE': 'Cannot reach the pickup',
  'SAFETY': 'Safety concern',
  'OTHER': 'Other',
};
