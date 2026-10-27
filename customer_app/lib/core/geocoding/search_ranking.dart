import '../location/place.dart';
import 'place_identity.dart';

/// Relevance tiers for a nearby search. A lower tier ranks first.
enum MatchTier {
  /// Found by its mapped feature (for example railway=station), so it matches the category exactly.
  mappedFeature(0),

  /// Found by a text search on the query words.
  textMatch(1);

  const MatchTier(this.rank);

  final int rank;
}

/// A place together with the strategy that found it.
class ScoredPlace {
  const ScoredPlace(this.place, this.tier);

  final Place place;
  final MatchTier tier;
}

double _distance(Place place) => place.distanceMeters ?? double.infinity;

/// Merges results from several strategies for one nearby search.
///
/// Duplicates are removed by [placeIdentity], and the best tier wins for each place.
/// Places beyond [radiusMeters] are dropped. The rest are ordered by tier (mapped features first),
/// then by distance from the GPS origin, so the closest matching place comes first.
List<Place> rankNearby(Iterable<ScoredPlace> hits, {required double radiusMeters}) {
  final best = <String, ScoredPlace>{};
  for (final hit in hits) {
    if (_distance(hit.place) > radiusMeters) continue;
    final key = placeIdentity(hit.place);
    final existing = best[key];
    if (existing == null || hit.tier.rank < existing.tier.rank) {
      best[key] = hit;
    }
  }

  final ranked = best.values.toList()
    ..sort((a, b) {
      final byTier = a.tier.rank.compareTo(b.tier.rank);
      if (byTier != 0) return byTier;
      return _distance(a.place).compareTo(_distance(b.place));
    });
  return [for (final hit in ranked) hit.place];
}

/// Places beyond [radiusMeters] that were found by an expanded search, closest first.
List<Place> rankBeyond(Iterable<ScoredPlace> hits, {required double radiusMeters}) {
  final far = dedupePlaces([
    for (final hit in hits)
      if (_distance(hit.place) > radiusMeters) hit.place,
  ])
    ..sort((a, b) => _distance(a).compareTo(_distance(b)));
  return far;
}

/// Results of a named-place search, in the order the search service returned them.
/// The GPS origin does not reorder them.
List<Place> rankExplicit(Iterable<Place> places) => dedupePlaces(places);
