import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/ride.dart';

class RideRepository {
  RideRepository(this._api);

  final ApiClient _api;

  Future<List<Ride>> rides({String? status}) async {
    final response = await _api.send((dio) => dio.get<dynamic>(
          ApiEndpoints.rides,
          queryParameters: {'status': ?status},
        ));
    final data = response.data;
    final list = data is Map ? (data['results'] as List? ?? const []) : (data as List? ?? const []);
    return [for (final item in list) Ride.fromJson(item as Map<String, dynamic>)];
  }

  Future<Ride> ride(String id) async {
    final response = await _api.send((dio) => dio.get<Map<String, dynamic>>(ApiEndpoints.ride(id)));
    return Ride.fromJson(response.data!);
  }

  Future<Ride> _action(String id, String action, [Map<String, dynamic>? body]) async {
    final response = await _api.send(
      (dio) => dio.post<Map<String, dynamic>>(ApiEndpoints.rideAction(id, action), data: body),
    );
    return Ride.fromJson(response.data!);
  }

  Future<Ride> accept(String id) => _action(id, 'accept');

  Future<void> reject(String id) async {
    await _api.send((dio) => dio.post<dynamic>(ApiEndpoints.rideAction(id, 'reject')));
  }

  Future<Ride> arrived(String id) => _action(id, 'arrived');

  /// [pin] is the rider's 4-digit start code, when the platform requires it.
  Future<Ride> start(String id, {String pin = ''}) => _action(id, 'start', {'pin': pin});

  Future<Ride> complete(String id) => _action(id, 'complete');

  Future<void> cancel(String id, {required String reason, String note = ''}) async {
    await _api.send((dio) => dio.post<dynamic>(
          ApiEndpoints.rideAction(id, 'cancel'),
          data: {'reason': reason, 'note': note},
        ));
  }

  Future<Ride> collectCash(String id) => _action(id, 'collect-cash');
}
