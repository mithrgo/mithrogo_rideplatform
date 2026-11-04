import 'dart:async';

import 'package:customer_app/app/providers.dart';
import 'package:customer_app/core/geocoding/nearby_feature_service.dart';
import 'package:customer_app/core/geocoding/place_category.dart';
import 'package:customer_app/core/geocoding/place_search_service.dart';
import 'package:customer_app/core/location/city_defaults.dart';
import 'package:customer_app/core/location/lat_lng.dart';
import 'package:customer_app/core/location/location_service.dart';
import 'package:customer_app/core/location/place.dart';
import 'package:customer_app/features/booking/application/place_search_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rider's GPS position as the tests see it. [failure] makes the next fix fail.
class _Gps {
  _Gps({this.fix, this.failure});

  LatLng? fix;
  LocationFailure? failure;
}

/// The backend place search. Records every call with the origin and query it was given.
class _FakeBackend implements PlaceSearchService {
  _FakeBackend(this.handler);

  final Future<NearbyPlaces> Function(String query, LatLng origin) handler;
  final calls = <({String query, LatLng origin})>[];

  @override
  Future<NearbyPlaces> search(String query, {required LatLng origin}) {
    calls.add((query: query, origin: origin));
    return handler(query, origin);
  }
}

/// Mapped-feature search (Overpass). Records every call with the radius it was given.
class _FakeFeatures implements NearbyFeatureService {
  _FakeFeatures(this.handler);

  final Future<List<Place>> Function(PlaceCategory category, LatLng origin, double radius) handler;
  final calls = <({PlaceCategory category, LatLng origin, double radius})>[];

  @override
  Future<List<Place>> search(PlaceCategory category, {required LatLng origin, required double radiusMeters}) {
    calls.add((category: category, origin: origin, radius: radiusMeters));
    return handler(category, origin, radiusMeters);
  }
}

/// A place [metres] from the GPS origin the tests use.
Place _place(String id, String name, double metres) {
  return Place(
    id: id,
    name: name,
    address: '$name, Nizamabad',
    latitude: 18.6725,
    longitude: 78.0941,
    subtitle: 'Nizamabad · ${metres.round()} m away',
    distanceMeters: metres,
  );
}

/// The backend answer for a 3 km search, with the given places.
NearbyPlaces _answer(List<Place> places) => NearbyPlaces(radiusMeters: 3000, places: places);

const _gpsOrigin = LatLng(latitude: 18.7000, longitude: 78.1000);

ProviderContainer _container({
  required _FakeBackend backend,
  required _FakeFeatures features,
  required _Gps gps,
}) {
  final container = ProviderContainer(overrides: [
    placeSearchServiceProvider.overrideWithValue(backend),
    nearbyFeatureServiceProvider.overrideWithValue(features),
    placeSearchDebounceProvider.overrideWithValue(const Duration(milliseconds: 20)),
    currentLocationProvider.overrideWith((ref) async {
      if (gps.failure != null) {
        throw LocationException(gps.failure!, 'Location is unavailable in this test.');
      }
      return gps.fix!;
    }),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// Lets the debounce timer fire, then waits until the search has finished. A fixed delay alone is
/// too short when the test suite runs under load.
Future<void> _settle(ProviderContainer container) async {
  await Future<void>.delayed(const Duration(milliseconds: 40));
  for (var i = 0; i < 100 && _state(container).status == PlaceSearchStatus.loading; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

PlaceSearchController _search(ProviderContainer container) {
  // Keeps the autoDispose controller alive for the whole test.
  container.listen(placeSearchControllerProvider, (_, _) {});
  return container.read(placeSearchControllerProvider.notifier);
}

PlaceSearchState _state(ProviderContainer container) => container.read(placeSearchControllerProvider);

void main() {
  group('the search is centred on the real GPS position', () {
    test('the backend is asked once, with the actual GPS position as the origin', () async {
      final backend = _FakeBackend((_, _) async => _answer([_place('node:1', 'D Mart', 900)]));
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(backend: backend, features: features, gps: _Gps(fix: _gpsOrigin));

      _search(container).onQueryChanged('d mart');
      await _settle(container);

      expect(backend.calls.single.origin, _gpsOrigin);
      expect(backend.calls.single.query, 'd mart');
      expect(_state(container).status, PlaceSearchStatus.loaded);
    });

    test('no GPS position means no search and no stand-in origin', () async {
      final backend = _FakeBackend((_, _) async => _answer([]));
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(
        backend: backend,
        features: features,
        gps: _Gps(failure: LocationFailure.permissionDenied),
      );

      _search(container).onQueryChanged('d mart');
      await _settle(container);

      expect(backend.calls, isEmpty);
      expect(_state(container).status, PlaceSearchStatus.needsLocation);
      expect(_state(container).locationFailure, LocationFailure.permissionDenied);
    });

    test('a rider outside the city is searched around the city centre, and is told so', () async {
      final backend = _FakeBackend((_, _) async => _answer([_place('node:1', 'D Mart', 900)]));
      final features = _FakeFeatures((_, _, _) async => []);
      const farAway = LatLng(latitude: 17.3850, longitude: 78.4867);
      final container = _container(backend: backend, features: features, gps: _Gps(fix: farAway));

      _search(container).onQueryChanged('d mart');
      await _settle(container);

      expect(backend.calls.single.origin, nizamabadCenter);
      expect(_state(container).notice, contains(nizamabadLabel));
    });
  });

  group('results stay inside the backend radius', () {
    test('a place beyond the radius is not shown even if the backend returned it', () async {
      final backend = _FakeBackend((_, _) async => _answer([
            _place('node:near', 'D Mart Nizamabad', 2000),
            _place('node:far', 'D Mart Raipur', 412000),
          ]));
      final container = _container(
        backend: backend,
        features: _FakeFeatures((_, _, _) async => []),
        gps: _Gps(fix: _gpsOrigin),
      );

      _search(container).onQueryChanged('d mart');
      await _settle(container);

      expect(_state(container).nearby.map((p) => p.id), ['node:near']);
    });

    test('results are ordered nearest first', () async {
      final backend = _FakeBackend((_, _) async => _answer([
            _place('node:2', 'Two', 2400),
            _place('node:1', 'One', 300),
            _place('node:3', 'Three', 1500),
          ]));
      final container = _container(
        backend: backend,
        features: _FakeFeatures((_, _, _) async => []),
        gps: _Gps(fix: _gpsOrigin),
      );

      _search(container).onQueryChanged('mart');
      await _settle(container);

      expect(_state(container).nearby.map((p) => p.id), ['node:1', 'node:3', 'node:2']);
    });

    test('nothing nearby is an empty result, with no wider search', () async {
      final backend = _FakeBackend((_, _) async => _answer([]));
      final container = _container(
        backend: backend,
        features: _FakeFeatures((_, _, _) async => []),
        gps: _Gps(fix: _gpsOrigin),
      );

      _search(container).onQueryChanged('d mart');
      await _settle(container);

      expect(_state(container).status, PlaceSearchStatus.loaded);
      expect(_state(container).hasResults, isFalse);
      expect(_state(container).error, isNull);
      expect(backend.calls, hasLength(1), reason: 'no second search across India');
    });

    test('a named city does not bring in places outside the radius', () async {
      final backend = _FakeBackend((_, _) async => _answer([]));
      final container = _container(
        backend: backend,
        features: _FakeFeatures((_, _, _) async => []),
        gps: _Gps(fix: _gpsOrigin),
      );

      _search(container).onQueryChanged('railway station Hyderabad');
      await _settle(container);

      expect(backend.calls.single.query, 'railway station Hyderabad');
      expect(_state(container).hasResults, isFalse);
    });
  });

  group('mapped features (stations and similar)', () {
    test('use the backend radius, not a radius of their own', () async {
      final backend = _FakeBackend((_, _) async => _answer([]));
      final features = _FakeFeatures((_, _, _) async => [_place('node:st', 'Nizamabad Station', 1200)]);
      final container = _container(backend: backend, features: features, gps: _Gps(fix: _gpsOrigin));

      _search(container).onQueryChanged('railway');
      await _settle(container);

      expect(features.calls.single.radius, 3000);
      expect(features.calls.single.origin, _gpsOrigin);
      expect(_state(container).nearby.map((p) => p.id), ['node:st']);
    });

    test('a failing mapped-feature service leaves the text results and shows a notice', () async {
      final backend = _FakeBackend((_, _) async => _answer([_place('node:t', 'Railway Colony', 800)]));
      final features = _FakeFeatures((_, _, _) async => throw const PlaceSearchException('Nearby places are taking too long. Try again.'));
      final container = _container(backend: backend, features: features, gps: _Gps(fix: _gpsOrigin));

      _search(container).onQueryChanged('railway');
      await _settle(container);

      expect(_state(container).nearby.map((p) => p.id), ['node:t']);
      expect(_state(container).notice, 'Nearby places are taking too long. Try again.');
    });
  });

  group('failures', () {
    test('a backend failure is shown as an error, and nothing else is searched', () async {
      final backend = _FakeBackend((_, _) async => throw const PlaceSearchException('Could not reach place search.'));
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(backend: backend, features: features, gps: _Gps(fix: _gpsOrigin));

      _search(container).onQueryChanged('d mart');
      await _settle(container);

      expect(_state(container).status, PlaceSearchStatus.error);
      expect(_state(container).error, 'Could not reach place search.');
      expect(backend.calls, hasLength(1));
    });

    test('retry runs the same query again', () async {
      var attempts = 0;
      final backend = _FakeBackend((_, _) async {
        attempts++;
        if (attempts == 1) throw const PlaceSearchException('Search timed out. Try again.');
        return _answer([_place('node:1', 'D Mart', 900)]);
      });
      final container = _container(
        backend: backend,
        features: _FakeFeatures((_, _, _) async => []),
        gps: _Gps(fix: _gpsOrigin),
      );
      final search = _search(container);

      search.onQueryChanged('d mart');
      await _settle(container);
      await search.retry();

      expect(_state(container).status, PlaceSearchStatus.loaded);
      expect(_state(container).hasResults, isTrue);
    });
  });

  group('timing and caching', () {
    test('a stale response for an older query never replaces the newer results', () async {
      final slow = Completer<NearbyPlaces>();
      final backend = _FakeBackend((query, _) {
        if (query == 'old') return slow.future;
        return Future.value(_answer([_place('node:new', 'New result', 500)]));
      });
      final container = _container(
        backend: backend,
        features: _FakeFeatures((_, _, _) async => []),
        gps: _Gps(fix: _gpsOrigin),
      );

      final search = _search(container);
      search.onQueryChanged('old');
      await _settle(container);
      search.onQueryChanged('newer');
      await _settle(container);
      slow.complete(_answer([_place('node:old', 'Old result', 100)]));
      await _settle(container);

      expect(_state(container).query, 'newer');
      expect(_state(container).nearby.map((p) => p.id), ['node:new']);
    });

    test('the same query at the same spot is not sent again', () async {
      final backend = _FakeBackend((_, _) async => _answer([_place('node:1', 'D Mart', 900)]));
      final container = _container(
        backend: backend,
        features: _FakeFeatures((_, _, _) async => []),
        gps: _Gps(fix: _gpsOrigin),
      );
      final search = _search(container);

      search.onQueryChanged('d mart');
      await _settle(container);
      search.onQueryChanged('D Mart');
      await _settle(container);

      expect(backend.calls, hasLength(1));
    });

    test('a query shorter than the minimum is not sent', () async {
      final backend = _FakeBackend((_, _) async => _answer([]));
      final container = _container(
        backend: backend,
        features: _FakeFeatures((_, _, _) async => []),
        gps: _Gps(fix: _gpsOrigin),
      );

      _search(container).onQueryChanged('dm');
      await _settle(container);

      expect(backend.calls, isEmpty);
      expect(_state(container).status, PlaceSearchStatus.tooShort);
    });
  });
}
