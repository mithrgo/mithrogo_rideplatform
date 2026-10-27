import 'package:customer_app/core/geocoding/search_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isExplicitPlaceQuery', () {
    test('generic place types are not explicit, so they search near the rider', () {
      for (final query in ['railway', 'railway station', 'bus stand', 'hospital', 'petrol pump', 'Railway Station']) {
        expect(isExplicitPlaceQuery(query), isFalse, reason: query);
      }
    });

    test('a named city or locality makes the query explicit', () {
      expect(isExplicitPlaceQuery('railway station Hyderabad'), isTrue);
      expect(isExplicitPlaceQuery('Vinayak Nagar'), isTrue);
      expect(isExplicitPlaceQuery('nizamabad'), isTrue);
    });

    test('non-Latin letters count as words, so they are explicit', () {
      expect(isExplicitPlaceQuery('రైల్వే స్టేషన్'), isTrue);
    });

    test('punctuation and spacing do not create words', () {
      expect(isExplicitPlaceQuery('  railway,  station! '), isFalse);
    });
  });
}
