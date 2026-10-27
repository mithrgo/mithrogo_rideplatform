import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/vehicle.dart';

class VehicleRepository {
  VehicleRepository(this._api);

  final ApiClient _api;

  Future<List<Vehicle>> vehicles() async {
    final response = await _api.send((dio) => dio.get<dynamic>(ApiEndpoints.vehicles));
    final data = response.data;
    final list = data is Map ? (data['results'] as List? ?? const []) : (data as List? ?? const []);
    return [for (final item in list) Vehicle.fromJson(item as Map<String, dynamic>)];
  }

  Future<Vehicle> add({
    required String type,
    required String registrationNumber,
    required String make,
    required String model,
    required String color,
  }) async {
    final response = await _api.send((dio) => dio.post<Map<String, dynamic>>(ApiEndpoints.vehicles, data: {
          'vehicle_type': type,
          'registration_number': registrationNumber,
          'make': make,
          'model': model,
          'color': color,
        }));
    return Vehicle.fromJson(response.data!);
  }

  Future<void> chooseForToday(String type) async {
    await _api.send((dio) => dio.post<Map<String, dynamic>>(ApiEndpoints.vehicleOfDay, data: {'vehicle_type': type}));
  }
}
