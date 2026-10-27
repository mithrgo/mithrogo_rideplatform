import '../../../core/utils/json.dart';

/// Result of captains/status/: whether the captain may go online, and why not.
class CaptainStatusInfo {
  const CaptainStatusInfo({
    required this.onlineStatus,
    required this.todayVehicleType,
    required this.eligible,
    required this.reasons,
    required this.message,
  });

  factory CaptainStatusInfo.fromJson(Map<String, dynamic> json) {
    return CaptainStatusInfo(
      onlineStatus: (json['online_status'] as String?) ?? 'OFFLINE',
      todayVehicleType: json['today_vehicle_type'] as String?,
      eligible: json['eligible'] == true,
      reasons: [for (final r in (json['reasons'] as List? ?? const [])) r.toString()],
      message: (json['message'] as String?) ?? '',
    );
  }

  final String onlineStatus;
  final String? todayVehicleType;
  final bool eligible;
  final List<String> reasons;
  final String message;

  bool get isOnline => onlineStatus == 'ONLINE' || onlineStatus == 'BUSY';

  bool get isBusy => onlineStatus == 'BUSY';

  bool needs(String reason) => reasons.contains(reason);
}

/// An open ride request from captains/offers/.
class RideOffer {
  const RideOffer({
    required this.rideId,
    required this.distanceKm,
    required this.expiresAt,
    required this.pickupAddress,
    required this.dropAddress,
    required this.fare,
    required this.vehicleType,
  });

  factory RideOffer.fromJson(Map<String, dynamic> json) {
    return RideOffer(
      rideId: json['ride_id'].toString(),
      distanceKm: parseDouble(json['distance_km']),
      expiresAt: DateTime.tryParse((json['expires_at'] as String?) ?? '') ?? DateTime.now(),
      pickupAddress: (json['pickup_address'] as String?) ?? '',
      dropAddress: (json['drop_address'] as String?) ?? '',
      fare: json['fare']?.toString() ?? '0',
      vehicleType: (json['vehicle_type'] as String?) ?? '',
    );
  }

  final String rideId;

  /// Distance from the captain to the pickup point.
  final double distanceKm;
  final DateTime expiresAt;
  final String pickupAddress;
  final String dropAddress;
  final String fare;
  final String vehicleType;

  int get secondsLeft => expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 999);
}
