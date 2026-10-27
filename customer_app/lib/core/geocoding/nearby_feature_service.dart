import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../app/config/env.dart';
import '../location/lat_lng.dart';
import '../location/place.dart';
import 'place_category.dart';
import 'place_search_service.dart';

/// Finds mapped features (for example every railway station) within a radius of a point.
abstract class NearbyFeatureService {
  Future<List<Place>> search(PlaceCategory category, {required LatLng origin, required double radiusMeters});
}

/// Overpass API, `around:` queries. Coordinates in the query are latitude first, as Overpass expects.
///
/// Usage: one request per category search, cached in memory, with a 25 second server timeout.
/// The public instance is shared and rate-limited, so this is for development and light testing.
class OverpassNearbyFeatureService implements NearbyFeatureService {
  OverpassNearbyFeatureService({
    http.Client? client,
    String? baseUrl,
    String? userAgent,
    this.timeout = const Duration(seconds: 30),
  })  : _client = client ?? http.Client(),
        _baseUrl = Uri.parse(baseUrl ?? Env.overpassBaseUrl),
        _userAgent = userAgent ?? Env.searchUserAgent;

  final http.Client _client;
  final Uri _baseUrl;
  final String _userAgent;
  final Duration timeout;

  static const _maxCacheEntries = 20;
  final Map<String, Future<List<Place>>> _cache = {};

  @override
  Future<List<Place>> search(PlaceCategory category, {required LatLng origin, required double radiusMeters}) {
    final key = '${category.name}|${origin.latitude.toStringAsFixed(4)},${origin.longitude.toStringAsFixed(4)}|'
        '${radiusMeters.round()}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final request = _fetch(category, origin, radiusMeters);
    _cache[key] = request;
    if (_cache.length > _maxCacheEntries) _cache.remove(_cache.keys.first);
    return request.catchError((Object error) {
      _cache.remove(key);
      throw error;
    });
  }

  Future<List<Place>> _fetch(PlaceCategory category, LatLng origin, double radiusMeters) async {
    final query = buildOverpassQuery(category, origin: origin, radiusMeters: radiusMeters);

    final http.Response response;
    try {
      response = await _client
          .post(
            _baseUrl,
            headers: {'User-Agent': _userAgent, 'Content-Type': 'application/x-www-form-urlencoded'},
            body: {'data': query},
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const PlaceSearchException('Nearby places are taking too long. Try again.');
    } catch (_) {
      throw const PlaceSearchException('Could not reach the nearby places service.');
    }

    // 429 and 504 mean the shared server is busy. Ask the rider to wait, rather than retrying in a loop.
    if (response.statusCode == 429 || response.statusCode == 504) {
      throw const PlaceSearchException('Nearby places service is busy. Wait a moment and try again.');
    }
    if (response.statusCode != 200) {
      throw PlaceSearchException('Nearby places service is unavailable (HTTP ${response.statusCode}).');
    }
    return parseOverpassResponse(response.body, category: category, origin: origin);
  }

  void close() => _client.close();

  /// Visible for tests. Builds an Overpass QL query for every tagged node, way or relation within the radius.
  static String buildOverpassQuery(PlaceCategory category, {required LatLng origin, required double radiusMeters}) {
    final around = 'around:${radiusMeters.round()},${origin.latitude.toStringAsFixed(6)},${origin.longitude.toStringAsFixed(6)}';
    final filters = [
      for (final pair in category.tags) 'nwr["${pair[0]}"="${pair[1]}"]($around);',
    ].join('\n  ');
    return '[out:json][timeout:25];\n(\n  $filters\n);\nout body center;';
  }
}

/// Reads an Overpass JSON response. Visible for tests.
///
/// Nodes give their own coordinates. Ways and relations give `center`. Each element keeps its
/// OpenStreetMap identity ("node:123"), which matches Nominatim's `osm_type:osm_id`, so the same
/// feature from both services is recognised as one place.
List<Place> parseOverpassResponse(String body, {required PlaceCategory category, required LatLng origin}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const PlaceSearchException('Invalid response from the nearby places service.');
  }
  if (decoded is! Map<String, dynamic> || decoded['elements'] is! List) {
    throw const PlaceSearchException('Invalid response from the nearby places service.');
  }

  final places = <Place>[];
  for (final element in decoded['elements'] as List) {
    if (element is! Map<String, dynamic>) continue;

    final type = element['type'];
    final id = element['id'];
    final center = element['center'] is Map<String, dynamic> ? element['center'] as Map<String, dynamic> : element;
    final latitude = (center['lat'] as num?)?.toDouble();
    final longitude = (center['lon'] as num?)?.toDouble();
    if (type is! String || id is! num || latitude == null || longitude == null) continue;

    final point = LatLng(latitude: latitude, longitude: longitude);
    if (!point.isValid) continue;

    final tags = element['tags'] is Map<String, dynamic> ? element['tags'] as Map<String, dynamic> : const <String, dynamic>{};
    final name = _text(tags['name']) ?? _text(tags['name:en']);
    final locality = _text(tags['addr:suburb']) ??
        _text(tags['addr:neighbourhood']) ??
        _text(tags['addr:village']) ??
        _text(tags['addr:city']);
    final state = _text(tags['addr:state']);
    final distance = point.distanceTo(origin);

    places.add(Place(
      // A mapped feature without a name is labelled by its category, never with an invented name.
      name: name ?? '${category.label} (unnamed)',
      address: name ?? category.label,
      latitude: latitude,
      longitude: longitude,
      subtitle: [
        ?locality,
        if (state != null && state != locality) state,
        distanceLabel(distance),
      ].join(' · '),
      id: '$type:${id.toInt()}',
      distanceMeters: distance,
    ));
  }
  return places;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
