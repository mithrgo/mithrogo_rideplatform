import 'dart:convert';

import 'package:customer_app/core/location/lat_lng.dart';
import 'package:customer_app/core/routing/route_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _pickup = LatLng(latitude: 18.5204, longitude: 73.8567);
const _drop = LatLng(latitude: 18.5590, longitude: 73.7868);
final _base = Uri.parse('https://router.project-osrm.org');

String _okBody({
  List<List<double>> coordinates = const [
    [73.8567, 18.5204],
    [73.8000, 18.5400],
    [73.7868, 18.5590],
  ],
  num distance = 8450.4,
  num duration = 1234,
}) {
  return jsonEncode({
    'code': 'Ok',
    'routes': [
      {
        'distance': distance,
        'duration': duration,
        'geometry': {'type': 'LineString', 'coordinates': coordinates},
      },
    ],
  });
}

void main() {
  group('buildUri', () {
    test('puts longitude before latitude and asks for GeoJSON geometry', () {
      final uri = OsrmRouteService.buildUri(_base, from: _pickup, to: _drop);

      expect(uri.host, 'router.project-osrm.org');
      expect(
        uri.path,
        '/route/v1/driving/73.856700,18.520400;73.786800,18.559000',
      );
      expect(uri.queryParameters['geometries'], 'geojson');
      expect(uri.queryParameters['overview'], 'full');
    });

    test('keeps a path prefix on a self-hosted OSRM base URL', () {
      final uri = OsrmRouteService.buildUri(
        Uri.parse('https://maps.example.com/osrm/'),
        from: _pickup,
        to: _drop,
      );

      expect(uri.path, startsWith('/osrm/route/v1/driving/'));
    });
  });

  group('parseOsrmResponse', () {
    test('converts GeoJSON [lng, lat] pairs into LatLng in the right order', () {
      final result = parseOsrmResponse(200, _okBody());

      expect(result.points, hasLength(3));
      expect(result.points.first.latitude, 18.5204);
      expect(result.points.first.longitude, 73.8567);
      expect(result.points.last.latitude, 18.5590);
      expect(result.points.last.longitude, 73.7868);
    });

    test('reads distance in metres and duration in seconds', () {
      final result = parseOsrmResponse(200, _okBody(distance: 8450.4, duration: 1234));

      expect(result.distanceMeters, 8450.4);
      expect(result.durationSeconds, 1234);
    });

    test('formats distance and duration for display', () {
      final short = parseOsrmResponse(200, _okBody(distance: 850, duration: 45));
      expect(short.distanceLabel, '850 m');
      expect(short.durationLabel, '1 min');

      final long = parseOsrmResponse(200, _okBody(distance: 8450.4, duration: 3900));
      expect(long.distanceLabel, '8.5 km');
      expect(long.durationLabel, '1 h 5 min');

      final instant = parseOsrmResponse(200, _okBody(duration: 10));
      expect(instant.durationLabel, '1 min');
      final zero = parseOsrmResponse(200, _okBody(duration: 0));
      expect(zero.durationLabel, '<1 min');
    });

    test('NoRoute code becomes a readable no-route error', () {
      expect(
        () => parseOsrmResponse(200, jsonEncode({'code': 'NoRoute', 'message': 'Impossible route'})),
        throwsA(isA<RouteException>().having((e) => e.message, 'message', contains('No driving route'))),
      );
    });

    test('empty routes list is treated as no route', () {
      expect(
        () => parseOsrmResponse(200, jsonEncode({'code': 'Ok', 'routes': []})),
        throwsA(isA<RouteException>()),
      );
    });

    test('HTTP failure becomes a service error', () {
      expect(
        () => parseOsrmResponse(503, '<html>Service unavailable</html>'),
        throwsA(isA<RouteException>().having((e) => e.message, 'message', contains('HTTP 503'))),
      );
    });

    test('non-JSON body on a 200 is an invalid response', () {
      expect(
        () => parseOsrmResponse(200, 'not json'),
        throwsA(isA<RouteException>().having((e) => e.message, 'message', contains('Invalid response'))),
      );
    });

    test('a route with too few points is invalid', () {
      expect(
        () => parseOsrmResponse(200, _okBody(coordinates: const [[73.85, 18.52]])),
        throwsA(isA<RouteException>()),
      );
    });

    test('missing geometry fields are invalid, not a crash', () {
      final body = jsonEncode({
        'code': 'Ok',
        'routes': [
          {'distance': 100},
        ],
      });
      expect(() => parseOsrmResponse(200, body), throwsA(isA<RouteException>()));
    });
  });

  group('OsrmRouteService', () {
    test('sends the request and returns the parsed route', () async {
      Uri? requested;
      final client = MockClient((request) async {
        requested = request.url;
        return http.Response(_okBody(), 200);
      });
      final service = OsrmRouteService(client: client, baseUrl: _base.toString());

      final result = await service.route(from: _pickup, to: _drop);

      expect(requested?.path, '/route/v1/driving/73.856700,18.520400;73.786800,18.559000');
      expect(result.points, hasLength(3));
    });

    test('a slow server times out with a readable message', () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response(_okBody(), 200);
      });
      final service = OsrmRouteService(
        client: client,
        baseUrl: _base.toString(),
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        service.route(from: _pickup, to: _drop),
        throwsA(isA<RouteException>().having((e) => e.message, 'message', contains('timed out'))),
      );
    });

    test('a network failure becomes a RouteException', () async {
      final client = MockClient((request) async {
        throw http.ClientException('no connection');
      });
      final service = OsrmRouteService(client: client, baseUrl: _base.toString());

      await expectLater(
        service.route(from: _pickup, to: _drop),
        throwsA(isA<RouteException>()),
      );
    });
  });
}
