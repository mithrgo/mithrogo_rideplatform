import '../../app/config/env.dart';

/// Thrown when the driving route is longer than the ride limit.
class RideTooFarException implements Exception {
  const RideTooFarException({required this.distanceMeters, required this.limitMeters});

  final double distanceMeters;
  final int limitMeters;

  /// Safe to show to the rider.
  String get message {
    final km = (distanceMeters / 1000).toStringAsFixed(1);
    final limitKm = (limitMeters / 1000).round();
    return 'This trip is $km km by road. Rides are limited to $limitKm km. Choose a closer drop point.';
  }

  @override
  String toString() => 'RideTooFarException: $message';
}

/// Rejects a route longer than [limitMeters]. A route of exactly the limit is allowed.
void ensureWithinRideLimit(
  double distanceMeters, {
  int limitMeters = Env.maxRideDistanceMeters,
}) {
  if (distanceMeters > limitMeters) {
    throw RideTooFarException(distanceMeters: distanceMeters, limitMeters: limitMeters);
  }
}
