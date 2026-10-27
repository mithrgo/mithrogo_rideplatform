import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/env.dart';
import '../../../app/providers.dart';
import '../../../core/geocoding/place_category.dart';
import '../../../core/geocoding/place_identity.dart';
import '../../../core/geocoding/place_search_service.dart';
import '../../../core/geocoding/search_intent.dart';
import '../../../core/geocoding/search_ranking.dart';
import '../../../core/location/city_defaults.dart';
import '../../../core/location/lat_lng.dart';
import '../../../core/location/location_service.dart';
import '../../../core/location/place.dart';
import '../../../core/location/service_area.dart';
import '../../../core/network/api_exception.dart';

/// Waits this long after the last keystroke before searching.
final placeSearchDebounceProvider = Provider<Duration>((ref) => const Duration(milliseconds: 450));

/// Nominatim and Overpass ask for modest request rates. Tests override this to zero.
final placeSearchMinIntervalProvider = Provider<Duration>((ref) => const Duration(seconds: 1));

enum PlaceSearchStatus {
  idle,
  tooShort,
  loading,

  /// A nearby search cannot run without the rider's GPS position.
  needsLocation,
  loaded,
  error,
}

/// One finished search, kept in memory so the same query is not sent again.
class _SearchAnswer {
  const _SearchAnswer({
    required this.explicit,
    required this.nearby,
    required this.beyond,
    required this.canExpand,
    this.notice,
  });

  final bool explicit;
  final List<Place> nearby;
  final List<Place> beyond;
  final bool canExpand;
  final String? notice;
}

class PlaceSearchState {
  const PlaceSearchState({
    this.query = '',
    this.status = PlaceSearchStatus.idle,
    this.explicit = false,
    this.nearby = const [],
    this.beyond = const [],
    this.canExpand = false,
    this.expanded = false,
    this.locationFailure,
    this.error,
    this.notice,
  });

  final String query;
  final PlaceSearchStatus status;

  /// True for a named place such as "railway station Hyderabad". Such a search is not tied to the GPS position.
  final bool explicit;

  /// Places within the nearby radius of the GPS position, best match first, then closest.
  final List<Place> nearby;

  /// Places beyond the nearby radius. Only filled after the rider chooses "Expand search area".
  final List<Place> beyond;

  /// True when a nearby search found nothing and the rider may widen it.
  final bool canExpand;
  final bool expanded;

  /// Set with [PlaceSearchStatus.needsLocation], so the screen can offer Settings or retry.
  final LocationFailure? locationFailure;
  final String? error;

  /// Shown above results, for example when one search source was unavailable.
  final String? notice;

  bool get hasResults => nearby.isNotEmpty || beyond.isNotEmpty;
}

/// Destination and pickup search.
///
/// Nearby searches (generic words such as "railway", "bus stand", "hospital") centre on the
/// customer's real GPS position. Without a valid position they do not run, and nothing else stands
/// in for it. Named-place searches ("railway station Hyderabad") run without the GPS position.
class PlaceSearchController extends AutoDisposeNotifier<PlaceSearchState> {
  static const minQueryLength = 3;
  static const _maxCacheEntries = 30;

  /// Waits longer than the GPS service's own timeout, so a slow fix is not cut short.
  static const _locationWait = Duration(seconds: 20);

  Timer? _debounce;
  DateTime? _lastRequestAt;

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
    _debounce = Timer(ref.read(placeSearchDebounceProvider), () => _run(query, id, expand: false));
  }

  /// Runs the current query again. After a location failure it asks the device for a fresh fix.
  Future<void> retry() {
    final query = state.query;
    if (query.length < minQueryLength) return Future.value();
    if (state.status == PlaceSearchStatus.needsLocation) {
      ref.invalidate(currentLocationProvider);
    }
    return _run(query, ++_requestId, expand: state.expanded);
  }

  /// Searches across a wider area. Only offered when the nearby search found nothing.
  Future<void> expandSearch() {
    final query = state.query;
    if (query.length < minQueryLength) return Future.value();
    return _run(query, ++_requestId, expand: true);
  }

  /// Called when the GPS position changes, for example after a fresh fix arrives. A nearby search
  /// that is waiting for a position, or that used an older one, runs again from the new position.
  void onLocationChanged() {
    final query = state.query;
    if (state.explicit || query.length < minQueryLength) return;
    if (state.status == PlaceSearchStatus.loading || state.status == PlaceSearchStatus.idle) return;
    _run(query, ++_requestId, expand: state.expanded);
  }

  Future<void> _run(String query, int id, {required bool expand}) async {
    // A query with a place name in it ("venu mall", "railway station hyderabad") also looks across
    // India, but places near the rider are always listed first.
    final explicit = isExplicitPlaceQuery(query);
    if (explicit) expand = false;

    // The origin is the rider's real position while they are inside the city. Outside it, nearby
    // results would be places the rider cannot book, so the search is centred on the city instead.
    final LatLng gps;
    try {
      gps = await ref.read(currentLocationProvider.future).timeout(_locationWait);
    } on LocationException catch (error) {
      if (id != _requestId) return;
      // A named place can still be found without a position.
      if (explicit) return _runExplicit(query, id);
      state = PlaceSearchState(
        query: query,
        status: PlaceSearchStatus.needsLocation,
        locationFailure: error.failure,
        error: error.message,
      );
      return;
    } catch (_) {
      if (id != _requestId) return;
      if (explicit) return _runExplicit(query, id);
      state = const PlaceSearchState(
        status: PlaceSearchStatus.needsLocation,
        locationFailure: LocationFailure.unavailable,
        error: 'Could not get your location. Try again, or choose a pickup point.',
      );
      return;
    }
    if (id != _requestId) return;
    final origin = searchOriginFor(gps);
    final outsideCity = origin != gps;

    final key = '${explicit ? 'named' : 'nearby'}|${query.toLowerCase()}|${_originKey(origin)}|$expand';
    final cached = _cache[key];
    if (cached != null) {
      state = _stateFrom(query, cached, expanded: expand);
      return;
    }

    state = PlaceSearchState(query: query, status: PlaceSearchStatus.loading, expanded: expand, explicit: explicit);

    final radius = Env.localSearchRadiusMeters.toDouble();
    final expandedRadius = Env.expandedSearchRadiusMeters.toDouble();
    // A named place is not found by its type, so mapped features are only for generic queries.
    final category = explicit ? null : categoryForQuery(query);
    final hits = <ScoredPlace>[];
    final failures = <String>[];
    var strategies = 0;

    // The two strategies talk to different servers, so they run at the same time. Whichever answers
    // first is shown right away, and the other one fills in when it arrives.
    void showPartial() {
      if (id != _requestId) return;
      final partial = rankNearby(hits, radiusMeters: radius);
      if (partial.isEmpty) return;
      state = _stateFrom(
        query,
        _SearchAnswer(explicit: explicit, nearby: partial, beyond: const [], canExpand: false),
        expanded: expand,
      );
    }

    var mappedFailed = false;

    // Strategy 1: mapped features (railway=station and similar). Finds stations that are not named "railway".
    Future<void> mappedFeatures(PlaceCategory category) async {
      try {
        final features = await ref.read(nearbyFeatureServiceProvider).search(
              category,
              origin: origin,
              radiusMeters: expand ? expandedRadius : radius,
            );
        hits.addAll(features.map((p) => ScoredPlace(p, MatchTier.mappedFeature)));
        showPartial();
      } on PlaceSearchException catch (error) {
        failures.add(error.message);
        mappedFailed = true;
      }
    }

    // Strategy 2: text search. Nearby is bounded to the radius. Expanded is biased toward the origin.
    // Only this one is throttled: the limit is Nominatim's, and Overpass is a separate server.
    Future<void> textSearch() async {
      try {
        await _throttle();
        if (id != _requestId) return;
        final texts = await ref.read(placeSearchServiceProvider).search(
              query,
              origin: origin,
              scope: expand ? SearchScope.wide : SearchScope.nearby,
            );
        hits.addAll(texts.map((p) => ScoredPlace(p, MatchTier.textMatch)));
        showPartial();
      } on PlaceSearchException catch (error) {
        failures.add(error.message);
      }
    }

    // Strategy 3, named places only: all of India, ranked toward the rider. It is listed after
    // the nearby matches, in the order the search service returned it.
    final wide = <Place>[];
    Future<void> wideSearch() async {
      try {
        await _throttle();
        if (id != _requestId) return;
        wide.addAll(await ref.read(placeSearchServiceProvider).search(query, origin: origin, scope: SearchScope.wide));
      } on PlaceSearchException catch (error) {
        failures.add(error.message);
      }
    }

    strategies = (category == null ? 1 : 2) + (explicit ? 1 : 0);
    await Future.wait([
      if (category != null) mappedFeatures(category),
      textSearch(),
      if (explicit) wideSearch(),
    ]);
    if (id != _requestId) return;

    // The mapped-feature server is down, and a half-typed word like "rail" matches no name. Ask the
    // text search for the kind of place by its full name instead ("Railway station").
    if (mappedFailed && category != null && category.label.toLowerCase() != query.toLowerCase()) {
      try {
        await _throttle();
        if (id != _requestId) return;
        final byLabel = await ref.read(placeSearchServiceProvider).search(
              category.label,
              origin: origin,
              scope: expand ? SearchScope.wide : SearchScope.nearby,
            );
        hits.addAll(byLabel.map((p) => ScoredPlace(p, MatchTier.textMatch)));
      } on PlaceSearchException {
        // The failure from the first attempt is already shown.
      }
      if (id != _requestId) return;
    }

    if (hits.isEmpty && wide.isEmpty && failures.length == strategies) {
      state = PlaceSearchState(query: query, status: PlaceSearchStatus.error, expanded: expand, error: _riderMessage(failures.first));
      return;
    }

    final nearby = rankNearby(hits, radiusMeters: radius);
    final nearbyKeys = {for (final place in nearby) placeIdentity(place)};
    final beyond = explicit
        ? [for (final place in rankExplicit(wide)) if (!nearbyKeys.contains(placeIdentity(place))) place]
        : expand
            ? rankBeyond(hits, radiusMeters: radius)
            : const <Place>[];
    final answer = _SearchAnswer(
      explicit: explicit,
      nearby: nearby,
      beyond: beyond,
      canExpand: !explicit && !expand && nearby.isEmpty,
      notice: [
        if (outsideCity) 'You are outside the service area, so these are places near $nizamabadLabel.',
        // Raw server errors (HTTP 403 and the like) mean nothing to a rider, and the other strategies
        // already filled in the results.
        ...failures.where((message) => !message.contains('HTTP')),
      ].join(' ').nullIfEmpty,
    );
    _logSearch(origin, expand: expand, hits: hits, answer: answer, expandedRadius: expandedRadius);

    _remember(key, answer);
    state = _stateFrom(query, answer, expanded: expand);
  }

  String _riderMessage(String message) =>
      message.contains('HTTP') ? 'Could not load places right now. Please try again.' : message;

  /// A named place: searched across India, independent of the GPS position.
  Future<void> _runExplicit(String query, int id) async {
    final key = 'explicit|${query.toLowerCase()}';
    final cached = _cache[key];
    if (cached != null) {
      state = _stateFrom(query, cached, expanded: false);
      return;
    }

    state = PlaceSearchState(query: query, status: PlaceSearchStatus.loading, explicit: true);
    try {
      await _throttle();
      if (id != _requestId) return;
      final results = await ref.read(placeSearchServiceProvider).search(query, scope: SearchScope.wide);
      if (id != _requestId) return;

      // Nominatim's order is kept. Distance from the GPS position would reorder a named city's results.
      final answer = _SearchAnswer(
        explicit: true,
        nearby: const [],
        beyond: rankExplicit(results),
        canExpand: false,
      );
      _remember(key, answer);
      state = _stateFrom(query, answer, expanded: false);
    } catch (error) {
      if (id != _requestId) return;
      state = PlaceSearchState(
        query: query,
        status: PlaceSearchStatus.error,
        explicit: true,
        error: userMessage(error),
      );
    }
  }

  /// Waits for the rate limit before each network call.
  Future<void> _throttle() async {
    final last = _lastRequestAt;
    if (last != null) {
      final wait = ref.read(placeSearchMinIntervalProvider) - DateTime.now().difference(last);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    _lastRequestAt = DateTime.now();
  }

  void _remember(String key, _SearchAnswer answer) {
    _cache[key] = answer;
    if (_cache.length > _maxCacheEntries) _cache.remove(_cache.keys.first);
  }

  PlaceSearchState _stateFrom(String query, _SearchAnswer answer, {required bool expanded}) {
    return PlaceSearchState(
      query: query,
      status: PlaceSearchStatus.loaded,
      explicit: answer.explicit,
      // For a named place, the Nominatim results are shown in the "beyond" list, labelled as across India.
      nearby: answer.nearby,
      beyond: answer.beyond,
      canExpand: answer.canExpand,
      expanded: expanded,
      notice: answer.notice,
    );
  }

  /// Rounded to about 10 metres, so a fix that barely moved does not repeat the request, but a real move does.
  String _originKey(LatLng origin) =>
      '${origin.latitude.toStringAsFixed(4)},${origin.longitude.toStringAsFixed(4)}';

  /// Temporary diagnostics for the nearby search. Counts and strategy names only: no query text,
  /// no coordinates. Remove once the search is verified on a device.
  void _logSearch(
    LatLng origin, {
    required bool expand,
    required List<ScoredPlace> hits,
    required _SearchAnswer answer,
    required double expandedRadius,
  }) {
    if (!kDebugMode) return;
    final mapped = hits.where((h) => h.tier == MatchTier.mappedFeature).length;
    debugPrint('[place-search] nearby origin=gps expanded=$expand '
        'hits(mapped=$mapped, text=${hits.length - mapped}) '
        'shown(nearby=${answer.nearby.length}, beyond=${answer.beyond.length}) '
        'radiusKm=${Env.localSearchRadiusMeters ~/ 1000} expandedRadiusKm=${expandedRadius ~/ 1000}');
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

final placeSearchControllerProvider =
    NotifierProvider.autoDispose<PlaceSearchController, PlaceSearchState>(PlaceSearchController.new);
