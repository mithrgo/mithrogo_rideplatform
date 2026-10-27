import 'package:customer_app/core/geocoding/place_category.dart';
import 'package:customer_app/core/geocoding/search_intent.dart';
import 'package:customer_app/core/geocoding/search_ranking.dart';
import 'package:customer_app/core/location/place.dart';
import 'package:flutter_test/flutter_test.dart';

Place _place(String id, String name, double metres) {
  return Place(
    id: id,
    name: name,
    address: name,
    latitude: 18.67,
    longitude: 78.09,
    distanceMeters: metres,
  );
}

void main() {
  group('rankNearby', () {
    test('removes duplicates across strategies, keeping the better tier', () {
      final ranked = rankNearby([
        ScoredPlace(_place('node:1', 'Station', 5000), MatchTier.textMatch),
        ScoredPlace(_place('node:1', 'Station', 5000), MatchTier.mappedFeature),
      ], radiusMeters: 30000);

      expect(ranked.map((p) => p.id), ['node:1']);
    });

    test('mapped features rank before text matches, even when a text match is closer', () {
      final ranked = rankNearby([
        ScoredPlace(_place('node:text', 'Railway Colony', 500), MatchTier.textMatch),
        ScoredPlace(_place('node:mapped', 'Nizamabad', 8000), MatchTier.mappedFeature),
      ], radiusMeters: 30000);

      expect(ranked.map((p) => p.id), ['node:mapped', 'node:text']);
    });

    test('within one tier, closer places come first', () {
      final ranked = rankNearby([
        ScoredPlace(_place('node:far', 'A', 9000), MatchTier.mappedFeature),
        ScoredPlace(_place('node:near', 'B', 1000), MatchTier.mappedFeature),
      ], radiusMeters: 30000);

      expect(ranked.map((p) => p.id), ['node:near', 'node:far']);
    });

    test('places beyond the radius are dropped', () {
      final ranked = rankNearby([
        ScoredPlace(_place('node:1', 'A', 29999), MatchTier.textMatch),
        ScoredPlace(_place('node:2', 'B', 30001), MatchTier.mappedFeature),
      ], radiusMeters: 30000);

      expect(ranked.map((p) => p.id), ['node:1']);
    });

    test('a place with no distance is never treated as nearby', () {
      const unknown = Place(name: 'Unknown', address: 'x', latitude: 18.67, longitude: 78.09);
      final ranked = rankNearby([ScoredPlace(unknown, MatchTier.mappedFeature)], radiusMeters: 30000);

      expect(ranked, isEmpty);
    });
  });

  group('rankBeyond', () {
    test('keeps only places beyond the radius, closest first, without duplicates', () {
      final beyond = rankBeyond([
        ScoredPlace(_place('node:near', 'A', 1000), MatchTier.textMatch),
        ScoredPlace(_place('node:far', 'B', 400000), MatchTier.textMatch),
        ScoredPlace(_place('node:mid', 'C', 90000), MatchTier.mappedFeature),
        ScoredPlace(_place('node:mid', 'C', 90000), MatchTier.textMatch),
      ], radiusMeters: 30000);

      expect(beyond.map((p) => p.id), ['node:mid', 'node:far']);
    });
  });

  group('rankExplicit', () {
    test('keeps the order the search returned and removes repeats', () {
      final ranked = rankExplicit([
        _place('node:h2', 'Hyderabad 2', 150000),
        _place('node:h1', 'Hyderabad 1', 152000),
        _place('node:h2', 'Hyderabad 2', 150000),
      ]);

      expect(ranked.map((p) => p.id), ['node:h2', 'node:h1']);
    });
  });

  group('categoryForQuery', () {
    test('railway words map to railway stations', () {
      expect(categoryForQuery('railway'), PlaceCategory.railwayStation);
      expect(categoryForQuery('railway station'), PlaceCategory.railwayStation);
      expect(categoryForQuery('Railways'), PlaceCategory.railwayStation);
    });

    test('bus words map to bus stations', () {
      expect(categoryForQuery('bus stand'), PlaceCategory.busStation);
      expect(categoryForQuery('bus'), PlaceCategory.busStation);
    });

    test('hospital maps to hospitals; other words have no category', () {
      expect(categoryForQuery('hospital'), PlaceCategory.hospital);
      expect(categoryForQuery('station'), isNull);
      expect(categoryForQuery('petrol pump'), isNull);
    });

    test('a named place is explicit, so a category does not override it', () {
      expect(isExplicitPlaceQuery('railway station Hyderabad'), isTrue);
    });
  });
}
