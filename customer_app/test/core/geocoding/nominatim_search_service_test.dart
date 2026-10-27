import 'dart:convert';

import 'package:customer_app/core/geocoding/place_search_service.dart';
import 'package:customer_app/core/location/city_defaults.dart';
import 'package:customer_app/core/location/lat_lng.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _base = Uri.parse('https://nominatim.openstreetmap.org');

/// A Nominatim jsonv2 answer, in Nominatim's own order (not distance order).
/// Ahmedabad and a US result come first; the nearby Nizamabad station comes after them.
final _sampleBody = jsonEncode([
  {
    'lat': '23.0225',
    'lon': '72.5714',
    'name': 'Railway Station',
    'display_name': 'Railway Station, Kalupur, Ahmedabad, Gujarat, India',
    'address': {'suburb': 'Kalupur', 'state': 'Gujarat', 'country_code': 'in'},
    'osm_type': 'node',
    'osm_id': 111,
  },
  {
    'lat': '40.0',
    'lon': '-74.0',
    'name': 'Railway Station',
    'display_name': 'Railway Station, New Jersey, USA',
    'address': {'state': 'New Jersey', 'country_code': 'us'},
    'osm_type': 'node',
    'osm_id': 222,
  },
  {
    'lat': '18.6800',
    'lon': '78.0900',
    'name': 'Railway Station',
    'display_name': 'Railway Station, Station Road, Nizamabad, Telangana, India',
    'address': {'neighbourhood': 'Station Road', 'city': 'Nizamabad', 'state': 'Telangana', 'country_code': 'in'},
    'osm_type': 'node',
    'osm_id': 333,
  },
]);

void main() {
  group('viewboxAround and localViewbox', () {
    test('viewboxAround is left,top,right,bottom: min lon, max lat, max lon, min lat', () {
      expect(viewboxAround(nizamabadCenter, 0.5), '77.594100,19.172500,78.594100,18.172500');
    });

    test('localViewbox covers the radius plus a margin, north-south and east-west', () {
      final box = localViewbox(nizamabadCenter, 30000).split(',').map(double.parse).toList();
      final left = box[0];
      final top = box[1];
      final right = box[2];
      final bottom = box[3];

      // 30 km with a 25% margin is about 0.337 degrees of latitude.
      expect(top - nizamabadCenter.latitude, closeTo(0.337, 0.01));
      expect(nizamabadCenter.latitude - bottom, closeTo(0.337, 0.01));
      // Longitude degrees are shorter at this latitude, so the east-west span is wider in degrees.
      expect(right - nizamabadCenter.longitude, greaterThan(top - nizamabadCenter.latitude));
      expect(left, lessThan(nizamabadCenter.longitude));
    });
  });

  group('NominatimPlaceSearchService.buildSearchUri', () {
    test('nearby scope is bounded to the local box, so far-away matches cannot appear', () {
      final uri = NominatimPlaceSearchService.buildSearchUri(
        _base,
        query: ' railway ',
        origin: nizamabadCenter,
        scope: SearchScope.nearby,
      );

      expect(uri.path, '/search');
      expect(uri.queryParameters['q'], 'railway');
      expect(uri.queryParameters['bounded'], '1');
      expect(uri.queryParameters['viewbox'], localViewbox(nizamabadCenter, 30000));
      expect(uri.queryParameters['countrycodes'], 'in');
      expect(uri.queryParameters['format'], 'jsonv2');
      expect(uri.queryParameters['limit'], '40');
    });

    test('wide scope is only a bias: bounded=0 with the bias box, so named places anywhere in India appear', () {
      final uri = NominatimPlaceSearchService.buildSearchUri(
        _base,
        query: 'railway station hyderabad',
        origin: nizamabadCenter,
        scope: SearchScope.wide,
      );

      expect(uri.queryParameters['bounded'], '0');
      expect(uri.queryParameters['viewbox'], viewboxAround(nizamabadCenter, searchBiasHalfSpanDegrees));
      expect(uri.queryParameters['countrycodes'], 'in');
    });

    test('the nearby box is built from the origin passed in, so a GPS origin moves the box', () {
      const hyderabad = LatLng(latitude: 17.3850, longitude: 78.4867);
      final uri = NominatimPlaceSearchService.buildSearchUri(
        _base,
        query: 'railway',
        origin: hyderabad,
        scope: SearchScope.nearby,
      );

      expect(uri.queryParameters['viewbox'], localViewbox(hyderabad, 30000));
      expect(uri.queryParameters['viewbox'], isNot(localViewbox(nizamabadCenter, 30000)));
    });
  });

  group('parseNominatimResponse', () {
    test('reads lat and lon strings as latitude and longitude, not swapped', () {
      final places = parseNominatimResponse(_sampleBody, origin: nizamabadCenter);
      final nizamabadStation = places.firstWhere((p) => p.subtitle.contains('Station Road'));

      expect(nizamabadStation.latitude, 18.68);
      expect(nizamabadStation.longitude, 78.09);
    });

    test('keeps Nominatim ranking order; sorting is the controller\'s job', () {
      final places = parseNominatimResponse(_sampleBody, origin: nizamabadCenter);

      expect(places.map((p) => p.id), ['node:111', 'node:333']);
    });

    test('measures distance from the origin it is given, not from a fixed place', () {
      const hyderabad = LatLng(latitude: 17.3850, longitude: 78.4867);
      final fromNizamabad = parseNominatimResponse(_sampleBody, origin: nizamabadCenter);
      final fromHyderabad = parseNominatimResponse(_sampleBody, origin: hyderabad);

      final stationFromNizamabad = fromNizamabad.firstWhere((p) => p.id == 'node:333');
      final stationFromHyderabad = fromHyderabad.firstWhere((p) => p.id == 'node:333');

      // About 1 km from Nizamabad's centre, and about 150 km from Hyderabad.
      expect(stationFromNizamabad.distanceMeters!, lessThan(2000));
      expect(stationFromHyderabad.distanceMeters!, greaterThan(140000));
    });

    test('drops results outside India', () {
      final places = parseNominatimResponse(_sampleBody, origin: nizamabadCenter);

      expect(places.any((p) => p.id == 'node:222'), isFalse);
      expect(places, hasLength(2));
    });

    test('gives same-named places a locality and state so they can be told apart', () {
      final places = parseNominatimResponse(_sampleBody, origin: nizamabadCenter);
      final gujarat = places.firstWhere((p) => p.id == 'node:111');
      final telangana = places.firstWhere((p) => p.id == 'node:333');

      expect(telangana.subtitle, contains('Station Road'));
      expect(telangana.subtitle, contains('Telangana'));
      expect(gujarat.subtitle, contains('Gujarat'));
    });

    test('uses the OpenStreetMap type and id as the identity when present', () {
      final places = parseNominatimResponse(_sampleBody, origin: nizamabadCenter);

      expect(places.first.id, 'node:111');
    });

    test('keeps the address within the backend limit of 255 characters', () {
      final body = jsonEncode([
        {
          'lat': '18.6725',
          'lon': '78.0941',
          'name': 'Long',
          'display_name': 'A' * 400,
          'address': {'country_code': 'in'},
        },
      ]);

      expect(parseNominatimResponse(body, origin: nizamabadCenter).single.address.length, 255);
    });

    test('skips entries with unusable coordinates', () {
      final body = jsonEncode([
        {'lat': 'abc', 'lon': '78.0', 'name': 'Bad', 'display_name': 'Bad'},
        {'lat': '0', 'lon': '0', 'name': 'Null island', 'display_name': 'Null island'},
      ]);

      expect(parseNominatimResponse(body, origin: nizamabadCenter), isEmpty);
    });

    test('an empty array means no results, not an error', () {
      expect(parseNominatimResponse('[]', origin: nizamabadCenter), isEmpty);
    });

    test('a non-JSON or non-list body is an invalid response', () {
      expect(
        () => parseNominatimResponse('<html></html>', origin: nizamabadCenter),
        throwsA(isA<PlaceSearchException>()),
      );
      expect(
        () => parseNominatimResponse('{"error":"x"}', origin: nizamabadCenter),
        throwsA(isA<PlaceSearchException>()),
      );
    });
  });

  group('NominatimPlaceSearchService.search', () {
    test('sends the identifying User-Agent and the bounded nearby query', () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return http.Response(_sampleBody, 200);
      });
      final service = NominatimPlaceSearchService(client: client, baseUrl: _base.toString());

      final places = await service.search('railway', origin: nizamabadCenter, scope: SearchScope.nearby);

      expect(sent.headers['User-Agent'], 'MithrGo-CustomerApp/1.0');
      expect(sent.url.queryParameters['bounded'], '1');
      expect(places, isNotEmpty);
    });

    test('HTTP 429 is reported as too many searches', () async {
      final client = MockClient((request) async => http.Response('slow down', 429));
      final service = NominatimPlaceSearchService(client: client, baseUrl: _base.toString());

      await expectLater(
        service.search('hospital', origin: nizamabadCenter, scope: SearchScope.nearby),
        throwsA(isA<PlaceSearchException>().having((e) => e.message, 'message', contains('Too many'))),
      );
    });

    test('a network failure becomes a PlaceSearchException', () async {
      final client = MockClient((request) async => throw http.ClientException('offline'));
      final service = NominatimPlaceSearchService(client: client, baseUrl: _base.toString());

      await expectLater(
        service.search('hospital', origin: nizamabadCenter, scope: SearchScope.nearby),
        throwsA(isA<PlaceSearchException>()),
      );
    });
  });

  group('distanceLabel', () {
    test('metres under a kilometre, kilometres above', () {
      expect(distanceLabel(940), '940 m away');
      expect(distanceLabel(12400), '12.4 km away');
    });
  });
}
