import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/geocoding/place_category.dart';
import '../../../core/geocoding/place_search_service.dart';
import '../../../core/geocoding/search_ranking.dart';
import '../../../core/location/city_defaults.dart';
import '../../../core/location/lat_lng.dart';
import '../../../core/location/location_service.dart';
import '../../../core/location/place.dart';
import '../../../core/location/service_area.dart';

/// Waits this long after the last keystroke before searching.
final placeSearchDebounceProvider = Provider<Duration>((ref) => const Duration(milliseconds: 450));

enum PlaceSearchStatus {
  idle,
  tooShort,
  loading,

  /// The search centres on the customer's GPS position, so it cannot run without one.
  needsLocation,
  loaded,
  error,
}

/// One finished search, kept in memory so the same query is not sent again.
class _SearchAnswer {
  const _SearchAnswer({required this.nearby, required this.radiusMeters, this.notice});

  final List<Place> nearby;
  final double radiusMeters;
  final String? notice;
}

class PlaceSearchState {
  const PlaceSearchState({
    this.query = '',
    this.status = PlaceSearchStatus.idle,
    this.nearby = const [],
    this.radiusMeters,
    this.locationFailure,
    this.error,
    this.notice,
  });

  final String query;
  final PlaceSearchStatus status;

  /// Places inside the backend search radius, best match first, then nearest.
  final List<Place> nearby;

  /// The backend's search radius, once a search has run.
  final double? radiusMeters;

  /// Set with [PlaceSearchStatus.needsLocation], so the screen can offer Settings or retry.
  final LocationFailure? locationFailure;
  final String? error;

  /// Shown above results, for example when one search source was unavailable.
  final String? notice;

  bool get hasResults => nearby.isNotEmpty;
}

/// Destination and pickup search.
///
/// Every search centres on the customer's real GPS position and is answered by the backend, which
/// returns only places inside its configured search radius. There is no search across India and no
/// wider fallback. Without a valid position nothing runs, and nothing else stands in for it.
class PlaceSearchController extends AutoDisposeNotifier<PlaceSearchState> {
  static const minQueryLength = 3;
  static const _maxCacheEntries = 30;

  /// Waits longer than the GPS service's own timeout, so a slow fix is not cut short.
  static const _locationWait = Duration(seconds: 20);

  Timer? _debounce;

  // Bumped by every keystroke, location change and search. A response applies only if its id is still the latest.
  int _requestId = 0;
  final Map<String, _SearchAnswer> _cache = {};

  @override
  PlaceSearchState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const PlaceSearchState();
  }

  /// Called on every keystroke. Only the last text after the debounce is searched.
  void onQueryChanged(String input) {
    final query = input.trim();
    _debounce?.cancel();
    final id = ++_requestId;

    if (query.length < minQueryLength) {
      state = PlaceSearchState(query: query, status: PlaceSearchStatus.tooShort);
      return;
    }

    state = PlaceSearchState(query: query, status: PlaceSearchStatus.loading);
    _debounce = Timer(ref.read(placeSearchDebounceProvider), () => _run(query, id));
  }

  /// Runs the current query again. After a location failure it asks the device for a fresh fix.
  Future<void> retry() {
    final query = state.query;
    if (query.length < minQueryLength) return Future.value();
    if (state.status == PlaceSearchStatus.needsLocation) {
      ref.invalidate(currentLocationProvider);
    }
    return _run(query, ++_requestId);
  }

  /// Called when the GPS position changes, for example after a fresh fix arrives. A search that is
  /// waiting for a position, or that used an older one, runs again from the new position.
  void onLocationChanged() {
    final query = state.query;
    if (query.length < minQueryLength) return;
    if (state.status == PlaceSearchStatus.loading || state.status == PlaceSearchStatus.idle) return;
    _run(query, ++_requestId);
  }

  Future<void> _run(String query, int id) async {
    // The origin is the rider's real position while they are inside the city. Outside it, nearby
    // results would be places the rider cannot book, so the search is centred on the city instead.
    final LatLng gps;
    try {
      gps = await ref.read(currentLocationProvider.future).timeout(_locationWait);
    } on LocationException catch (error) {
      if (id != _requestId) return;
      state = PlaceSearchState(
        query: query,
        status: PlaceSearchStatus.needsLocation,
        locationFailure: error.failure,
        error: error.message,
      );
      return;
    } catch (_) {
      if (id != _requestId) return;
      state = PlaceSearchState(
        query: query,
        status: PlaceSearchStatus.needsLocation,
        locationFailure: LocationFailure.unavailable,
        error: 'Could not get your location. Try again, or choose a pickup point.',
      );
      return;
    }
    if (id != _requestId) return;
    final origin = searchOriginFor(gps);
    final outsideCity = origin != gps;

    final key = '${query.toLowerCase()}|${_originKey(origin)}';
    final cached = _cache[key];
    if (cached != null) {
      state = _stateFrom(query, cached);
      return;
    }

    state = PlaceSearchState(query: query, status: PlaceSearchStatus.loading);

    final NearbyPlaces found;
    try {
      found = await ref.read(placeSearchServiceProvider).search(query, origin: origin);
    } on PlaceSearchException catch (error) {
      if (id != _requestId) return;
      state = PlaceSearchState(query: query, status: PlaceSearchStatus.error, error: error.message);
      return;
    }
    if (id != _requestId) return;

    final hits = [for (final place in found.places) ScoredPlace(place, MatchTier.textMatch)];
    final notices = <String>[];

    // Mapped features (railway=station and similar) find stations that are not named "railway". They
    // use the same radius as the backend search, so nothing outside it can appear.
    final category = categoryForQuery(query);
    if (category != null) {
      try {
        final features = await ref.read(nearbyFeatureServiceProvider).search(
              category,
              origin: origin,
              radiusMeters: found.radiusMeters,
            );
        if (id != _requestId) return;
        hits.addAll(features.map((p) => ScoredPlace(p, MatchTier.mappedFeature)));
      } on PlaceSearchException catch (error) {
        // Raw server errors (HTTP 403 and the like) mean nothing to a rider. The text results still show.
        if (!error.message.contains('HTTP')) notices.add(error.message);
      }
    }

    final answer = _SearchAnswer(
      nearby: rankNearby(hits, radiusMeters: found.radiusMeters),
      radiusMeters: found.radiusMeters,
      notice: [
        if (outsideCity) 'You are outside the service area, so these are places near $nizamabadLabel.',
        ...notices,
      ].join(' ').nullIfEmpty,
    );
    _remember(key, answer);
    state = _stateFrom(query, answer);
  }

  void _remember(String key, _SearchAnswer answer) {
    _cache[key] = answer;
    if (_cache.length > _maxCacheEntries) _cache.remove(_cache.keys.first);
  }

  PlaceSearchState _stateFrom(String query, _SearchAnswer answer) {
    return PlaceSearchState(
      query: query,
      status: PlaceSearchStatus.loaded,
      nearby: answer.nearby,
      radiusMeters: answer.radiusMeters,
      notice: answer.notice,
    );
  }

  /// Rounded to about 10 metres, so a fix that barely moved does not repeat the request, but a real move does.
  String _originKey(LatLng origin) =>
      '${origin.latitude.toStringAsFixed(4)},${origin.longitude.toStringAsFixed(4)}';
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

final placeSearchControllerProvider =
    NotifierProvider.autoDispose<PlaceSearchController, PlaceSearchState>(PlaceSearchController.new);
