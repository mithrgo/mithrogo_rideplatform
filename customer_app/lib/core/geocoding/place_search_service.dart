import '../location/lat_lng.dart';
import '../location/place.dart';
import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../network/api_exception.dart';

/// Shown in the search list when a query fails.
class PlaceSearchException implements Exception {
  const PlaceSearchException(this.message);

  final String message;

  @override
  String toString() => 'PlaceSearchException: $message';
}

/// Places the backend found inside its search radius, nearest first.
class NearbyPlaces {
  const NearbyPlaces({required this.radiusMeters, required this.places});

  /// The backend's configured search radius (PlatformConfig.search_radius_km), in metres.
  final double radiusMeters;
  final List<Place> places;
}

abstract class PlaceSearchService {
  /// Places matching [query] within the backend search radius of [origin], the rider's GPS position.
  /// Nothing outside that radius is returned, and there is no wider search.
  Future<NearbyPlaces> search(String query, {required LatLng origin});
}

/// Destination search through the backend, which queries the map data and applies the radius.
class BackendPlaceSearchService implements PlaceSearchService {
  BackendPlaceSearchService(this._api);

  final ApiClient _api;

  @override
  Future<NearbyPlaces> search(String query, {required LatLng origin}) async {
    final Map<String, dynamic> body;
    try {
      final response = await _api.send((dio) => dio.get<Map<String, dynamic>>(
            ApiEndpoints.placeSearch,
            queryParameters: {'q': query, 'lat': origin.latitude, 'lng': origin.longitude},
          ));
      body = response.data ?? const {};
    } on ApiException catch (error) {
      throw PlaceSearchException(error.message);
    }
    return parseNearbyPlaces(body);
  }
}

/// Reads the backend's `{"radius_km": ..., "results": [...]}` response. Visible for tests.
NearbyPlaces parseNearbyPlaces(Map<String, dynamic> body) {
  final radiusKm = body['radius_km'];
  final results = body['results'];
  if (radiusKm is! num || results is! List) {
    throw const PlaceSearchException('Invalid response from place search.');
  }

  final places = <Place>[];
  for (final item in results) {
    if (item is! Map<String, dynamic>) continue;
    final latitude = item['latitude'];
    final longitude = item['longitude'];
    final name = item['name'];
    if (latitude is! num || longitude is! num || name is! String || name.isEmpty) continue;

    final address = item['address'];
    final distanceKm = item['distance_km'];
    final distance = distanceKm is num ? distanceKm.toDouble() * 1000 : null;
    final distanceText = distance == null ? null : distanceLabel(distance);
    final locality = item['locality'] is String ? item['locality'] as String : null;
    final state = item['state'] is String ? item['state'] as String : null;

    places.add(Place(
      name: name,
      address: address is String ? address : name,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      subtitle: [
        ?locality,
        if (state != locality) ?state,
        ?distanceText,
      ].join(' · '),
      id: item['id'] is String ? item['id'] as String : null,
      distanceMeters: distance,
    ));
  }
  return NearbyPlaces(radiusMeters: radiusKm.toDouble() * 1000, places: places);
}

/// "940 m away" under a kilometre, otherwise "12.4 km away".
String distanceLabel(double metres) {
  if (metres < 1000) return '${metres.round()} m away';
  return '${(metres / 1000).toStringAsFixed(1)} km away';
}
