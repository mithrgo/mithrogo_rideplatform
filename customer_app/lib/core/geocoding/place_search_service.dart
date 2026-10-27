import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../app/config/env.dart';
import '../location/city_defaults.dart';
import '../location/lat_lng.dart';
import '../location/place.dart';

/// Shown in the search list when a query fails.
class PlaceSearchException implements Exception {
  const PlaceSearchException(this.message);

  final String message;

  @override
  String toString() => 'PlaceSearchException: $message';
}

/// How far a text search looks.
enum SearchScope {
  /// Only places inside the box around the GPS origin (Nominatim `bounded=1`). Needs an origin.
  nearby,

  /// Places anywhere in India (`bounded=0`). With an origin, the box only ranks nearer places first.
  wide,
}

abstract class PlaceSearchService {
  /// Places matching [query] in India.
  ///
  /// [origin] must be the customer's real GPS position for [SearchScope.nearby]. It is never a
  /// stand-in. For [SearchScope.wide] it may be null, and then nothing is biased.
  Future<List<Place>> search(String query, {LatLng? origin, required SearchScope scope});
}

/// Free-text place search on OpenStreetMap Nominatim. Coordinates come back as strings in
/// latitude, longitude order.
class NominatimPlaceSearchService implements PlaceSearchService {
  NominatimPlaceSearchService({
    http.Client? client,
    String? baseUrl,
    String? userAgent,
    this.timeout = const Duration(seconds: 8),
  })  : _client = client ?? http.Client(),
        _baseUrl = Uri.parse(baseUrl ?? Env.nominatimBaseUrl),
        _userAgent = userAgent ?? Env.searchUserAgent;

  final http.Client _client;
  final Uri _baseUrl;
  final String _userAgent;
  final Duration timeout;

  @override
  Future<List<Place>> search(String query, {LatLng? origin, required SearchScope scope}) async {
    if (scope == SearchScope.nearby && origin == null) {
      throw ArgumentError('A nearby search needs the GPS origin.');
    }
    final uri = buildSearchUri(_baseUrl, query: query, origin: origin, scope: scope);

    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'User-Agent': _userAgent, 'Accept-Language': 'en'})
          .timeout(timeout);
    } on TimeoutException {
      throw const PlaceSearchException('Search timed out. Try again.');
    } catch (_) {
      throw const PlaceSearchException('Could not reach place search. Check your connection.');
    }

    if (response.statusCode == 429) {
      throw const PlaceSearchException('Too many searches. Wait a moment and try again.');
    }
    if (response.statusCode != 200) {
      throw PlaceSearchException('Search is unavailable right now (HTTP ${response.statusCode}).');
    }
    return parseNominatimResponse(response.body, origin: origin);
  }

  void close() => _client.close();

  /// Visible for tests.
  ///
  /// Nearby: `bounded=1` returns only places inside the box, so far-away matches cannot appear.
  /// The box is a little larger than the radius, and distances are checked afterwards.
  ///
  /// Wide: `bounded=0`. The box, when there is an origin, only ranks nearer places first.
  static Uri buildSearchUri(
    Uri base, {
    required String query,
    LatLng? origin,
    required SearchScope scope,
    double? radiusMeters,
  }) {
    final prefix = base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path;
    final nearby = scope == SearchScope.nearby;
    final parameters = <String, String>{
      'q': query.trim(),
      'format': 'jsonv2',
      'addressdetails': '1',
      // Nominatim ranks by its own importance, so a small limit can drop the nearest match.
      'limit': '40',
      'countrycodes': 'in',
      'bounded': nearby ? '1' : '0',
      'accept-language': 'en',
    };
    if (nearby) {
      parameters['viewbox'] = localViewbox(origin!, radiusMeters ?? Env.localSearchRadiusMeters.toDouble());
    } else if (origin != null) {
      parameters['viewbox'] = viewboxAround(origin, searchBiasHalfSpanDegrees);
    }
    return base.replace(path: '$prefix/search', queryParameters: parameters);
  }
}

/// Nominatim viewbox: `left,top,right,bottom`, i.e. min longitude, max latitude, max longitude, min latitude.
String viewboxAround(LatLng center, double halfSpanDegrees) {
  return _box(center, halfSpanDegrees, halfSpanDegrees);
}

/// A box around [center] that covers [radiusMeters] with a 25% margin, in the same
/// `left,top,right,bottom` order.
String localViewbox(LatLng center, double radiusMeters) {
  const margin = 1.25;
  const metresPerDegreeLat = 111320.0;
  final dLat = radiusMeters * margin / metresPerDegreeLat;
  final dLng = dLat / math.cos(center.latitude * math.pi / 180);
  return _box(center, dLat, dLng);
}

String _box(LatLng center, double dLat, double dLng) {
  final left = center.longitude - dLng;
  final top = center.latitude + dLat;
  final right = center.longitude + dLng;
  final bottom = center.latitude - dLat;
  return '${left.toStringAsFixed(6)},${top.toStringAsFixed(6)},'
      '${right.toStringAsFixed(6)},${bottom.toStringAsFixed(6)}';
}

/// Maximum length of the backend's ride address fields.
const _maxAddressLength = 255;

/// Reads a Nominatim `jsonv2` search response. Visible for tests.
///
/// Results keep Nominatim's ranking. Each carries an OpenStreetMap id when one is given, a
/// subtitle with locality and state, and, when [origin] is known, its distance from it.
List<Place> parseNominatimResponse(String body, {LatLng? origin}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const PlaceSearchException('Invalid response from place search.');
  }
  if (decoded is! List) {
    throw const PlaceSearchException('Invalid response from place search.');
  }

  final places = <Place>[];
  for (final item in decoded) {
    if (item is! Map<String, dynamic>) continue;

    final latitude = double.tryParse('${item['lat']}');
    final longitude = double.tryParse('${item['lon']}');
    if (latitude == null || longitude == null) continue;

    final point = LatLng(latitude: latitude, longitude: longitude);
    if (!point.isValid) continue;

    final address = item['address'] is Map<String, dynamic>
        ? item['address'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final countryCode = address['country_code'];
    // Keep only India, even if the server returns something else.
    if (countryCode is String && countryCode.toLowerCase() != 'in') continue;

    final displayName = _text(item['display_name']);
    final name = _text(item['name']) ?? displayName?.split(',').first.trim() ?? '';
    if (name.isEmpty) continue;

    final distance = origin == null ? null : point.distanceTo(origin);
    final locality = _locality(address, exclude: name);
    final state = _text(address['state']);
    final osmType = _text(item['osm_type']);
    final osmId = item['osm_id'];

    places.add(Place(
      name: name,
      address: _truncate(displayName ?? name),
      latitude: latitude,
      longitude: longitude,
      subtitle: [
        ?locality,
        if (state != locality) ?state,
        if (distance != null) distanceLabel(distance),
      ].join(' · '),
      id: osmType != null && osmId != null ? '$osmType:$osmId' : null,
      distanceMeters: distance,
    ));
  }
  return places;
}

/// "940 m away" under a kilometre, otherwise "12.4 km away".
String distanceLabel(double metres) {
  if (metres < 1000) return '${metres.round()} m away';
  return '${(metres / 1000).toStringAsFixed(1)} km away';
}

const _localityKeys = [
  'neighbourhood',
  'suburb',
  'quarter',
  'village',
  'town',
  'city_district',
  'city',
  'municipality',
  'county',
];

String? _locality(Map<String, dynamic> address, {required String exclude}) {
  for (final key in _localityKeys) {
    final value = _text(address[key]);
    if (value != null && value != exclude) return value;
  }
  return null;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _truncate(String value) {
  return value.length <= _maxAddressLength ? value : value.substring(0, _maxAddressLength);
}
