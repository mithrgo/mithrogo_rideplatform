import 'dart:convert';

import 'package:customer_app/core/geocoding/nearby_feature_service.dart';
import 'package:customer_app/core/geocoding/place_category.dart';
import 'package:customer_app/core/geocoding/place_search_service.dart';
import 'package:customer_app/core/location/city_defaults.dart';
import 'package:customer_app/core/location/lat_lng.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _overpassUrl = Uri.parse('https://overpass-api.de/api/interpreter');

/// Overpass `out body center` output: a node with its own coordinates, and a way with a `center`.
final _sampleBody = jsonEncode({
  'elements': [
    {
      'type': 'node',
      'id': 1001,
      'lat': 18.6800,
      'lon': 78.0900,
      'tags': {'railway': 'station', 'name': 'Nizamabad Junction', 'addr:suburb': 'Station Road', 'addr:state': 'Telangana'},
    },
    {
      'type': 'way',
      'id': 2002,
      'center': {'lat': 18.6600, 'lon': 78.1100},
      'tags': {'railway': 'station', 'addr:city': 'Nizamabad'},
    },
    {
      'type': 'node',
      'id': 3003,
      'lat': 18.6700,
      'lon': 78.0950,
      'tags': {'railway': 'halt'},
    },
  ],
});

void main() {
  group('buildOverpassQuery', () {
    test('asks for mapped features around the GPS point, latitude first in the around filter', () {
      final query = OverpassNearbyFeatureService.buildOverpassQuery(
        PlaceCategory.railwayStation,
        origin: const LatLng(latitude: 18.7, longitude: 78.1),
        radiusMeters: 30000,
      );

      expect(query, contains('nwr["railway"="station"](around:30000,18.700000,78.100000);'));
      expect(query, contains('nwr["railway"="halt"](around:30000,18.700000,78.100000);'));
      expect(query, contains('out body center;'));
    });

    test('bus stations and hospitals use their own mapped tags', () {
      final bus = OverpassNearbyFeatureService.buildOverpassQuery(
        PlaceCategory.busStation,
        origin: nizamabadCenter,
        radiusMeters: 1000,
      );
      final hospital = OverpassNearbyFeatureService.buildOverpassQuery(
        PlaceCategory.hospital,
        origin: nizamabadCenter,
        radiusMeters: 1000,
      );

      expect(bus, contains('["amenity"="bus_station"]'));
      expect(hospital, contains('["amenity"="hospital"]'));
    });
  });

  group('parseOverpassResponse', () {
    test('reads node coordinates and way centres, in latitude, longitude order', () {
      final places = parseOverpassResponse(_sampleBody, category: PlaceCategory.railwayStation, origin: nizamabadCenter);

      final node = places.firstWhere((p) => p.id == 'node:1001');
      expect(node.latitude, 18.68);
      expect(node.longitude, 78.09);

      final way = places.firstWhere((p) => p.id == 'way:2002');
      expect(way.latitude, 18.66);
      expect(way.longitude, 78.11);
    });

    test('measures distance from the origin it is given', () {
      final places = parseOverpassResponse(_sampleBody, category: PlaceCategory.railwayStation, origin: nizamabadCenter);

      final node = places.firstWhere((p) => p.id == 'node:1001');
      expect(node.distanceMeters, closeTo(940, 300));
    });

    test('subtitle shows locality, state and distance', () {
      final places = parseOverpassResponse(_sampleBody, category: PlaceCategory.railwayStation, origin: nizamabadCenter);

      final node = places.firstWhere((p) => p.id == 'node:1001');
      expect(node.subtitle, contains('Station Road'));
      expect(node.subtitle, contains('Telangana'));
      expect(node.subtitle, contains('away'));
    });

    test('an unnamed feature is labelled by its category, not given an invented name', () {
      final places = parseOverpassResponse(_sampleBody, category: PlaceCategory.railwayStation, origin: nizamabadCenter);

      final halt = places.firstWhere((p) => p.id == 'node:3003');
      expect(halt.name, 'Railway station (unnamed)');
    });

    test('a response without elements is an invalid response', () {
      expect(
        () => parseOverpassResponse('{"remark":"runtime error"}', category: PlaceCategory.hospital, origin: nizamabadCenter),
        throwsA(isA<PlaceSearchException>()),
      );
    });
  });

  group('OverpassNearbyFeatureService.search', () {
    test('posts the query as form data with an identifying User-Agent', () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return http.Response(_sampleBody, 200);
      });
      final service = OverpassNearbyFeatureService(client: client, baseUrl: _overpassUrl.toString());

      final places = await service.search(PlaceCategory.railwayStation, origin: nizamabadCenter, radiusMeters: 30000);

      expect(sent.method, 'POST');
      expect(sent.headers['User-Agent'], 'MithrGo-CustomerApp/1.0');
      expect(sent.body, contains('data='));
      expect(places, isNotEmpty);
    });

    test('HTTP 429 asks the rider to wait instead of retrying in a loop', () async {
      final client = MockClient((request) async => http.Response('rate limited', 429));
      final service = OverpassNearbyFeatureService(client: client, baseUrl: _overpassUrl.toString());

      await expectLater(
        service.search(PlaceCategory.hospital, origin: nizamabadCenter, radiusMeters: 30000),
        throwsA(isA<PlaceSearchException>().having((e) => e.message, 'message', contains('busy'))),
      );
    });

    test('the same category and point are answered from memory', () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response(_sampleBody, 200);
      });
      final service = OverpassNearbyFeatureService(client: client, baseUrl: _overpassUrl.toString());

      await service.search(PlaceCategory.railwayStation, origin: nizamabadCenter, radiusMeters: 30000);
      await service.search(PlaceCategory.railwayStation, origin: nizamabadCenter, radiusMeters: 30000);

      expect(requests, 1);
    });
  });
}
