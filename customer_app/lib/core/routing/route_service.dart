import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../app/config/env.dart';
import '../location/lat_lng.dart';

/// A driving route with its geometry. Duration is OSRM's estimate, not a live-traffic ETA.
class RouteResult {
  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  /// "850 m" under a kilometre, otherwise "3.2 km".
  String get distanceLabel {
    if (distanceMeters < 1000) return '${distanceMeters.round()} m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  /// "<1 min", "12 min", or "1 h 5 min".
  String get durationLabel {
    final minutes = (durationSeconds / 60).ceil();
    if (minutes < 1) return '<1 min';
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${minutes % 60} min';
  }
}

/// Shown to the rider when a route cannot be calculated.
class RouteException implements Exception {
  const RouteException(this.message);

  final String message;

  @override
  String toString() => 'RouteException: $message';
}

abstract class RouteService {
  Future<RouteResult> route({required LatLng from, required LatLng to});
}

/// Driving routes from an OSRM server. Coordinates go out as longitude,latitude.
class OsrmRouteService implements RouteService {
  OsrmRouteService({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 10),
  })  : _client = client ?? http.Client(),
        _baseUrl = Uri.parse(baseUrl ?? Env.osrmBaseUrl);

  final http.Client _client;
  final Uri _baseUrl;
  final Duration timeout;

  // The same origin and destination are asked for by both the fare and the map route.
  // Keep recent answers so that is one request, not two. Failed requests are not kept.
  static const _maxCacheEntries = 20;
  final Map<String, Future<RouteResult>> _cache = {};

  @override
  Future<RouteResult> route({required LatLng from, required LatLng to}) async {
    final key = '${_lngLat(from)};${_lngLat(to)}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final request = _fetch(from, to);
    _cache[key] = request;
    if (_cache.length > _maxCacheEntries) _cache.remove(_cache.keys.first);
    try {
      return await request;
    } catch (_) {
      _cache.remove(key);
      rethrow;
    }
  }

  Future<RouteResult> _fetch(LatLng from, LatLng to) async {
    final uri = buildUri(_baseUrl, from: from, to: to);

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw const RouteException('Route request timed out. Try again.');
    } catch (_) {
      throw const RouteException('Could not reach the routing service. Check your connection.');
    }
    return parseOsrmResponse(response.statusCode, response.body);
  }

  void close() => _client.close();

  /// Visible for tests.
  static Uri buildUri(Uri base, {required LatLng from, required LatLng to}) {
    final prefix = base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path;
    final coordinates = '${_lngLat(from)};${_lngLat(to)}';
    return base.replace(
      path: '$prefix/route/v1/driving/$coordinates',
      queryParameters: const {'overview': 'full', 'geometries': 'geojson'},
    );
  }

  static String _lngLat(LatLng point) {
    return '${point.longitude.toStringAsFixed(6)},${point.latitude.toStringAsFixed(6)}';
  }
}

/// Reads an OSRM `route` response. Visible for tests.
RouteResult parseOsrmResponse(int statusCode, String body) {
  const noRoute = RouteException('No driving route found between these points.');
  const invalid = RouteException('Invalid response from the routing service.');

  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw statusCode == 200
        ? invalid
        : RouteException('Routing service unavailable (HTTP $statusCode).');
  }
  if (decoded is! Map<String, dynamic>) throw invalid;

  final code = decoded['code'];
  if (code == 'NoRoute' || code == 'NoSegment') throw noRoute;
  if (statusCode != 200) throw RouteException('Routing service unavailable (HTTP $statusCode).');
  if (code != 'Ok') throw invalid;

  final routes = decoded['routes'];
  if (routes is! List || routes.isEmpty) throw noRoute;

  try {
    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List;
    final points = [
      for (final pair in coordinates)
        // GeoJSON is [longitude, latitude].
        LatLng(
          latitude: ((pair as List)[1] as num).toDouble(),
          longitude: (pair[0] as num).toDouble(),
        ),
    ];
    if (points.length < 2) throw invalid;

    return RouteResult(
      points: points,
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
    );
  } on TypeError {
    throw invalid;
  }
}
