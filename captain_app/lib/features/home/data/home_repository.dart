import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/home_models.dart';

class HomeRepository {
  HomeRepository(this._api);

  final ApiClient _api;

  Future<CaptainStatusInfo> status() async {
    final response = await _api.send((dio) => dio.get<Map<String, dynamic>>(ApiEndpoints.status));
    return CaptainStatusInfo.fromJson(response.data!);
  }

  Future<void> goOnline() async {
    await _api.send((dio) => dio.post<Map<String, dynamic>>(ApiEndpoints.online));
  }

  Future<void> goOffline() async {
    await _api.send((dio) => dio.post<Map<String, dynamic>>(ApiEndpoints.offline));
  }

  Future<void> sendLocation({required double latitude, required double longitude, double? heading, double? speed}) async {
    await _api.send((dio) => dio.post<void>(ApiEndpoints.location, data: {
          'latitude': latitude.toStringAsFixed(6),
          'longitude': longitude.toStringAsFixed(6),
          if (heading != null && heading >= 0) 'heading': heading.toStringAsFixed(2),
          if (speed != null && speed >= 0) 'speed': speed.toStringAsFixed(2),
        }));
  }

  Future<List<RideOffer>> offers() async {
    final response = await _api.send((dio) => dio.get<dynamic>(ApiEndpoints.offers));
    final data = response.data;
    final list = data is Map ? (data['results'] as List? ?? const []) : (data as List? ?? const []);
    return [for (final item in list) RideOffer.fromJson(item as Map<String, dynamic>)];
  }
}
