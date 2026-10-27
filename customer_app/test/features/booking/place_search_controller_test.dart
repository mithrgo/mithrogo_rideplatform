import 'dart:async';

import 'package:customer_app/app/config/env.dart';
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

/// Text search (Nominatim). Records every call so a test can see the origin and scope used.
class _FakeText implements PlaceSearchService {
  _FakeText(this.handler);

  final Future<List<Place>> Function(String query, LatLng? origin, SearchScope scope) handler;
  final calls = <({String query, LatLng? origin, SearchScope scope})>[];

  @override
  Future<List<Place>> search(String query, {LatLng? origin, required SearchScope scope}) {
    calls.add((query: query, origin: origin, scope: scope));
    return handler(query, origin, scope);
  }
}

/// Mapped-feature search (Overpass). Records every call.
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

/// A result [metres] from the GPS origin the tests use.
Place _place(String id, String name, double metres) {
  return Place(
    id: id,
    name: name,
    address: '$name, Nizamabad',
    latitude: 18.6725,
    longitude: 78.0941,
    subtitle: 'Locality · Telangana · ${metres.round()} m away',
    distanceMeters: metres,
  );
}

const _gpsOrigin = LatLng(latitude: 18.7000, longitude: 78.1000);
const _nearMetres = 2000.0;
const _farMetres = 412000.0;

ProviderContainer _container({
  required _FakeText text,
  required _FakeFeatures features,
  required _Gps gps,
}) {
  final container = ProviderContainer(overrides: [
    placeSearchServiceProvider.overrideWithValue(text),
    nearbyFeatureServiceProvider.overrideWithValue(features),
    placeSearchDebounceProvider.overrideWithValue(const Duration(milliseconds: 20)),
    placeSearchMinIntervalProvider.overrideWithValue(Duration.zero),
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

/// Lets the debounce timer fire and the fake services get called.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 80));

PlaceSearchController _search(ProviderContainer container) {
  // Keeps the autoDispose controller alive for the whole test.
  container.listen(placeSearchControllerProvider, (_, _) {});
  return container.read(placeSearchControllerProvider.notifier);
}

PlaceSearchState _state(ProviderContainer container) => container.read(placeSearchControllerProvider);

void main() {
  group('GPS is the search origin', () {
    test('the actual GPS position is passed to the nearby text and mapped-feature searches', () async {
      final text = _FakeText((_, _, _) async => [_place('node:1', 'Railway Station', _nearMetres)]);
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(text: text, features: features, gps: _Gps(fix: _gpsOrigin));
      final search = _search(container);

      search.onQueryChanged('railway');
      await _settle();

      expect(text.calls.single.origin, _gpsOrigin);
      expect(text.calls.single.scope, SearchScope.nearby);
      expect(features.calls.single.origin, _gpsOrigin);
    });

    test('a GPS refresh replaces the older origin, and the search runs again from the new position', () async {
      const movedFix = LatLng(latitude: 18.6000, longitude: 78.2000);
      final gps = _Gps(fix: _gpsOrigin);
      final text = _FakeText((_, _, _) async => [_place('node:1', 'Railway Station', _nearMetres)]);
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(text: text, features: features, gps: gps);
      final search = _search(container);

      search.onQueryChanged('railway');
      await _settle();
      expect(text.calls.last.origin, _gpsOrigin);

      gps.fix = movedFix;
      container.invalidate(currentLocationProvider);
      search.onLocationChanged();
      await _settle();

      expect(text.calls.last.origin, movedFix);
      expect(features.calls.last.origin, movedFix);
    });

    test('an unchanged GPS fix does not repeat the search when the cache holds the answer', () async {
      final text = _FakeText((_, _, _) async => [_place('node:1', 'Railway Station', _nearMetres)]);
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(text: text, features: features, gps: _Gps(fix: _gpsOrigin));
      final search = _search(container);

      search.onQueryChanged('railway');
      await _settle();
      search.onQueryChanged('railway');
      await _settle();

      expect(text.calls, hasLength(1));
    });
  });

  group('missing GPS is never shown as Nizamabad', () {
    for (final failure in LocationFailure.values) {
      test('a nearby search with GPS $failure needs a location and calls no service', () async {
        final text = _FakeText((_, _, _) async => [_place('node:1', 'Railway Station', _nearMetres)]);
        final features = _FakeFeatures((_, _, _) async => []);
        final container = _container(text: text, features: features, gps: _Gps(failure: failure));
        final search = _search(container);

        search.onQueryChanged('railway');
        await _settle();

        final state = _state(container);
        expect(state.status, PlaceSearchStatus.needsLocation);
        expect(state.locationFailure, failure);
        expect(text.calls, isEmpty);
        expect(features.calls, isEmpty);
      });
    }

    test('no call ever uses the Nizamabad centre as an origin', () async {
      final text = _FakeText((_, _, _) async => []);
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(
        text: text,
        features: features,
        gps: _Gps(failure: LocationFailure.permissionDenied),
      );
      final search = _search(container);

      search.onQueryChanged('hospital');
      await _settle();

      expect(text.calls.any((c) => c.origin == nizamabadCenter), isFalse);
      expect(features.calls.any((c) => c.origin == nizamabadCenter), isFalse);
    });
  });

  group('railway and other categories', () {
    test('"railway" finds stations by their mapped feature, even when they are not named "railway"', () async {
      final text = _FakeText((_, _, _) async => []);
      final features = _FakeFeatures((category, _, _) async {
        expect(category, PlaceCategory.railwayStation);
        return [_place('node:55', 'Nizamabad', _nearMetres)];
      });
      final container = _container(text: text, features: features, gps: _Gps(fix: _gpsOrigin));
      final search = _search(container);

      search.onQueryChanged('railway');
      await _settle();

      expect(_state(container).nearby.map((p) => p.id), ['node:55']);
    });

    test('the mapped-feature search uses the configured radius around the GPS position', () async {
      final text = _FakeText((_, _, _) async => []);
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(text: text, features: features, gps: _Gps(fix: _gpsOrigin));
      final search = _search(container);

      search.onQueryChanged('bus stand');
      await _settle();

      expect(features.calls.single.category, PlaceCategory.busStation);
      expect(features.calls.single.radius, 30000);
    });
  });

  group('results from several strategies', () {
    test('they are de-duplicated, and mapped features rank before text matches', () async {
      final text = _FakeText((_, _, _) async => [
            _place('node:1', 'Railway Station', 5000),
            _place('node:2', 'Railway Colony', 1000),
          ]);
      final features = _FakeFeatures((_, _, _) async => [_place('node:1', 'Railway Station', 5000)]);
      final container = _container(text: text, features: features, gps: _Gps(fix: _gpsOrigin));
      final search = _search(container);

      search.onQueryChanged('railway');
      await _settle();

      expect(_state(container).nearby.map((p) => p.id), ['node:1', 'node:2']);
    });

    test('a failing strategy does not hide the others, and the rider sees a notice', () async {
      final text = _FakeText((_, _, _) async => [_place('node:9', 'Railway Station', _nearMetres)]);
      final features = _FakeFeatures((_, _, _) async => throw const PlaceSearchException('Nearby places service is busy.'));
      final container = _container(text: text, features: features, gps: _Gps(fix: _gpsOrigin));
      final search = _search(container);

      search.onQueryChanged('railway');
      await _settle();

      final state = _state(container);
      expect(state.status, PlaceSearchStatus.loaded);
      expect(state.nearby.map((p) => p.id), ['node:9']);
      expect(state.notice, contains('busy'));
    });
  });

  group('distant results are not shown by default', () {
    test('a far result from the nearby search is dropped, and expansion is offered', () async {
      final text = _FakeText((_, _, scope) async {
        if (scope == SearchScope.nearby) return [_place('node:9', 'Railway', _farMetres)];
        return [];
      });
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(text: text, features: features, gps: _Gps(fix: _gpsOrigin));
      final search = _search(container);

      search.onQueryChanged('railway');
      await _settle();

      final state = _state(container);
      expect(state.nearby, isEmpty);
      expect(state.beyond, isEmpty);
      expect(state.canExpand, isTrue);
    });
  });

  group('expanding the search area', () {
    test('"Expand search area" runs a wider search and lists far results separately, closest first', () async {
      final text = _FakeText((_, _, scope) async {
        if (scope == SearchScope.nearby) return [];
        return [_place('node:8', 'Railway', 900000), _place('node:9', 'Railway', _farMetres)];
      });
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(text: text, features: features, gps: _Gps(fix: _gpsOrigin));
      final search = _search(container);

      search.onQueryChanged('railway');
      await _settle();
      expect(_state(container).canExpand, isTrue);

      unawaited(search.expandSearch());
      await _settle();

      final state = _state(container);
      expect(state.expanded, isTrue);
      expect(state.beyond.map((p) => p.id), ['node:9', 'node:8']);
      expect(text.calls.last.scope, SearchScope.wide);
      expect(text.calls.last.origin, _gpsOrigin, reason: 'expansion is still centred on the real GPS position');
    });

    test('expansion is never run silently: a search with nearby results offers no expansion', () async {
      final text = _FakeText((_, _, _) async => [_place('node:1', 'Railway Station', _nearMetres)]);
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(text: text, features: features, gps: _Gps(fix: _gpsOrigin));
      final search = _search(container);

      search.onQueryChanged('railway');
      await _settle();

      expect(_state(container).canExpand, isFalse);
      expect(text.calls.map((c) => c.scope), [SearchScope.nearby]);
    });
  });

  group('explicit city searches', () {
    test('"railway station Hyderabad" searches the named city and ignores the GPS position', () async {
      final text = _FakeText((_, _, scope) async {
        if (scope == SearchScope.nearby) return [];
        return [
          _place('node:h1', 'Railway Station', 150000),
          _place('node:h2', 'Secunderabad Railway Station', 152000),
        ];
      });
      final features = _FakeFeatures((_, _, _) async => []);
      // GPS is unavailable: a named city must still work.
      final container = _container(text: text, features: features, gps: _Gps(failure: LocationFailure.permissionDenied));
      final search = _search(container);

      search.onQueryChanged('railway station hyderabad');
      await _settle();

      final state = _state(container);
      expect(state.status, PlaceSearchStatus.loaded);
      expect(state.explicit, isTrue);
      expect(state.beyond.map((p) => p.id), ['node:h1', 'node:h2'], reason: 'Nominatim order is kept');
      expect(features.calls, isEmpty, reason: 'a named city does not use mapped features near the GPS');
      expect(text.calls.single.origin, isNull, reason: 'no GPS bias for a named city');
      expect(text.calls.single.scope, SearchScope.wide);
    });

    test('a named city search does not reorder results by distance from the GPS position', () async {
      final text = _FakeText((_, _, _) async => [
            _place('node:far', 'Railway Station', 800000),
            _place('node:near', 'Railway Station', 1000),
          ]);
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(text: text, features: features, gps: _Gps(fix: _gpsOrigin));
      final search = _search(container);

      search.onQueryChanged('railway station hyderabad');
      await _settle();

      expect(_state(container).beyond.map((p) => p.id), ['node:far', 'node:near']);
    });
  });

  group('empty local results', () {
    test('show an explicit expansion option and do not silently search across India', () async {
      final text = _FakeText((_, _, _) async => []);
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(text: text, features: features, gps: _Gps(fix: _gpsOrigin));
      final search = _search(container);

      search.onQueryChanged('hospital');
      await _settle();

      final state = _state(container);
      expect(state.canExpand, isTrue);
      expect(text.calls.map((c) => c.scope), [SearchScope.nearby]);
    });
  });

  group('timing and stale responses', () {
    test('debounces typing: only the last text after the pause is searched', () async {
      final text = _FakeText((_, _, _) async => []);
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(text: text, features: features, gps: _Gps(fix: _gpsOrigin));
      final search = _search(container);

      search.onQueryChanged('rai');
      search.onQueryChanged('rail');
      search.onQueryChanged('railway');
      await _settle();

      expect(text.calls.map((c) => c.query).toSet(), {'railway'});
    });

    test('a query shorter than the minimum is not sent', () async {
      final text = _FakeText((_, _, _) async => []);
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(text: text, features: features, gps: _Gps(fix: _gpsOrigin));
      final search = _search(container);

      search.onQueryChanged('ra');
      await _settle();

      expect(text.calls, isEmpty);
      expect(_state(container).status, PlaceSearchStatus.tooShort);
    });

    test('a stale response for an old query never replaces the newer results', () async {
      final completers = <String, Completer<List<Place>>>{};
      final text = _FakeText((query, _, _) {
        return completers.putIfAbsent(query, () => Completer<List<Place>>()).future;
      });
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(text: text, features: features, gps: _Gps(fix: _gpsOrigin));
      final search = _search(container);

      search.onQueryChanged('bus stand');
      await _settle();
      search.onQueryChanged('hospital');
      await _settle();

      completers['hospital']!.complete([_place('node:h', 'Hospital', _nearMetres)]);
      await Future<void>.delayed(Duration.zero);
      completers['bus stand']!.complete([_place('node:b', 'Bus Stand', _nearMetres)]);
      await Future<void>.delayed(Duration.zero);

      final state = _state(container);
      expect(state.query, 'hospital');
      expect(state.nearby.map((p) => p.id), ['node:h']);
    });

    test('a failed search shows its message and retry runs it again', () async {
      var attempts = 0;
      final text = _FakeText((_, _, _) async {
        attempts++;
        if (attempts == 1) throw const PlaceSearchException('Search timed out. Try again.');
        return [_place('node:1', 'Hospital', _nearMetres)];
      });
      final features = _FakeFeatures((_, _, _) async => []);
      final container = _container(text: text, features: features, gps: _Gps(fix: _gpsOrigin));
      final search = _search(container);

      search.onQueryChanged('pharmacy');
      await _settle();

      var state = _state(container);
      expect(state.status, PlaceSearchStatus.error);
      expect(state.error, 'Search timed out. Try again.');

      unawaited(search.retry());
      await _settle();

      state = _state(container);
      expect(state.status, PlaceSearchStatus.loaded);
      expect(state.nearby.map((p) => p.id), ['node:1']);
    });
  });

  test('the nearby radius comes from configuration and is 30 km by default', () {
    expect(Env.localSearchRadiusMeters, 30000);
    expect(Env.expandedSearchRadiusMeters, 100000);
  });
}
