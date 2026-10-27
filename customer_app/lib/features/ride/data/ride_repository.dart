import 'package:dio/dio.dart';

import '../../../core/location/lat_lng.dart';
import '../../../core/location/place.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/ride.dart';
import '../models/ride_options.dart';
import '../models/ride_payment.dart';
import '../models/ride_tracking.dart';

class RideRepository {
  RideRepository(this._api);

  final ApiClient _api;

  Future<FareEstimate> estimate({
    required VehicleType vehicleType,
    required Place pickup,
    required Place drop,
  }) async {
    final response = await _api.send((dio) => dio.post<Map<String, dynamic>>(
          ApiEndpoints.rideEstimate,
          data: {..._route(pickup, drop), 'vehicle_type': vehicleType.apiValue},
        ));
    return FareEstimate.fromJson(response.data!);
  }

  /// [idempotencyKey] makes a retry after a timeout return the same ride instead of a second booking.
  Future<Ride> create({
    required Place pickup,
    required Place drop,
    required VehicleType vehicleType,
    required PaymentMethod paymentMethod,
    required String idempotencyKey,
    required LatLng deviceLocation,
    int tip = 0,
  }) async {
    final response = await _api.send((dio) => dio.post<Map<String, dynamic>>(
          ApiEndpoints.rides,
          data: {
            ..._route(pickup, drop),
            'vehicle_type': vehicleType.apiValue,
            'pickup_address': pickup.address,
            'drop_address': drop.address,
            'payment_method': paymentMethod.apiValue,
            // Where the booker is, which differs from the pickup when booking for a friend.
            'device_latitude': deviceLocation.latitude.toStringAsFixed(6),
            'device_longitude': deviceLocation.longitude.toStringAsFixed(6),
            if (tip > 0) 'tip': tip,
          },
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        ));
    return Ride.fromJson(response.data!);
  }

  Future<Ride> fetch(String rideId) async {
    final response = await _api.send((dio) => dio.get<Map<String, dynamic>>(ApiEndpoints.ride(rideId)));
    return Ride.fromJson(response.data!);
  }

  Future<RideTracking> tracking(String rideId) async {
    final response = await _api.send((dio) => dio.get<Map<String, dynamic>>(ApiEndpoints.rideTracking(rideId)));
    return RideTracking.fromJson(response.data!);
  }

  Future<Ride> cancel(String rideId) async {
    final response = await _api.send((dio) => dio.post<Map<String, dynamic>>(ApiEndpoints.rideCancel(rideId)));
    return Ride.fromJson(response.data!);
  }

  Future<void> rate(String rideId, {required int rating, String comment = ''}) async {
    await _api.send((dio) => dio.post<Map<String, dynamic>>(
          ApiEndpoints.rideRating(rideId),
          data: {'rating': rating, 'comment': comment},
        ));
  }

  /// Starts (or resumes) online payment for a completed ONLINE ride.
  Future<RidePayment> pay(String rideId) async {
    final response = await _api.send((dio) => dio.post<Map<String, dynamic>>(ApiEndpoints.ridePayment(rideId)));
    return RidePayment.fromJson(response.data!);
  }

  /// Reads a payment's status. The backend only marks it paid after the gateway webhook.
  Future<RidePayment> payment(String paymentId) async {
    final response = await _api.send((dio) => dio.get<Map<String, dynamic>>(ApiEndpoints.payment(paymentId)));
    return RidePayment.fromJson(response.data!);
  }

  Future<List<Ride>> history() async {
    final response = await _api.send((dio) => dio.get<List<dynamic>>(ApiEndpoints.rides));
    return (response.data ?? const <dynamic>[])
        .map((item) => Ride.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  // The backend takes decimal strings for coordinates, so floats never reach the wire.
  Map<String, dynamic> _route(Place pickup, Place drop) => {
        'pickup_latitude': pickup.latitude.toStringAsFixed(6),
        'pickup_longitude': pickup.longitude.toStringAsFixed(6),
        'drop_latitude': drop.latitude.toStringAsFixed(6),
        'drop_longitude': drop.longitude.toStringAsFixed(6),
      };
}
