import 'package:customer_app/core/geocoding/place_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseNearbyPlaces', () {
    test('reads the radius in metres and each place with its distance and subtitle', () {
      final result = parseNearbyPlaces({
        'radius_km': 3,
        'results': [
          {
            'id': 'node:1',
            'name': 'D Mart',
            'address': 'D Mart, Nizamabad, Telangana, India',
            'latitude': 18.6725,
            'longitude': 78.094,
            'distance_km': 0.94,
            'locality': 'Nizamabad',
            'state': 'Telangana',
          },
        ],
      });

      expect(result.radiusMeters, 3000);
      final place = result.places.single;
      expect(place.id, 'node:1');
      expect(place.name, 'D Mart');
      expect(place.distanceMeters, closeTo(940, 0.001));
      expect(place.subtitle, 'Nizamabad · Telangana · 940 m away');
    });

    test('keeps the order the backend sent, which is nearest first', () {
      final result = parseNearbyPlaces({
        'radius_km': 3,
        'results': [
          {'name': 'Near', 'latitude': 18.67, 'longitude': 78.09, 'distance_km': 0.2},
          {'name': 'Far', 'latitude': 18.69, 'longitude': 78.09, 'distance_km': 2.4},
        ],
      });

      expect(result.places.map((p) => p.name), ['Near', 'Far']);
    });

    test('skips a result with no name or coordinates instead of failing the whole search', () {
      final result = parseNearbyPlaces({
        'radius_km': 3,
        'results': [
          {'name': '', 'latitude': 18.67, 'longitude': 78.09},
          {'name': 'No position'},
          {'name': 'Good', 'latitude': 18.67, 'longitude': 78.09},
        ],
      });

      expect(result.places.map((p) => p.name), ['Good']);
    });

    test('an unexpected body is an error, not an empty list', () {
      expect(() => parseNearbyPlaces({'error': 'x'}), throwsA(isA<PlaceSearchException>()));
    });
  });

  group('distanceLabel', () {
    test('metres under a kilometre, kilometres above', () {
      expect(distanceLabel(940), '940 m away');
      expect(distanceLabel(12400), '12.4 km away');
    });
  });
}
