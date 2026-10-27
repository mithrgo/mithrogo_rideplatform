import 'package:customer_app/core/location/lat_lng.dart';
import 'package:customer_app/core/location/service_area.dart';
import 'package:customer_app/core/routing/ride_distance_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ensureWithinRideLimit (50 km)', () {
    const limit = 50000;

    test('a trip of 49.999 km is allowed', () {
      expect(() => ensureWithinRideLimit(49999, limitMeters: limit), returnsNormally);
    });

    test('a trip of exactly 50 km is allowed', () {
      expect(() => ensureWithinRideLimit(50000, limitMeters: limit), returnsNormally);
    });

    test('a trip of 50.001 km is blocked', () {
      expect(
        () => ensureWithinRideLimit(50001, limitMeters: limit),
        throwsA(isA<RideTooFarException>()),
      );
    });

    test('the message states the road distance and the limit in km', () {
      try {
        ensureWithinRideLimit(63400, limitMeters: limit);
        fail('expected RideTooFarException');
      } on RideTooFarException catch (error) {
        expect(error.message, contains('63.4 km by road'));
        expect(error.message, contains('limited to 50 km'));
      }
    });

    test('the limit can be changed per call, so it is configurable', () {
      expect(
        () => ensureWithinRideLimit(30000, limitMeters: 25000),
        throwsA(isA<RideTooFarException>()),
      );
    });

    test('the default limit comes from Env and is 50 km', () {
      // Env default, unless overridden with --dart-define=MAX_RIDE_DISTANCE_METERS.
      expect(() => ensureWithinRideLimit(50000), returnsNormally);
      expect(() => ensureWithinRideLimit(50500), throwsA(isA<RideTooFarException>()));
    });
  });

  group('LatLng', () {
    test('distanceTo gives straight-line metres for a known pair', () {
      const nizamabad = LatLng(latitude: 18.6725, longitude: 78.0941);
      const hyderabad = LatLng(latitude: 17.3850, longitude: 78.4867);

      // Roughly 153 km apart as the crow flies.
      final metres = nizamabad.distanceTo(hyderabad);
      expect(metres, greaterThan(145000));
      expect(metres, lessThan(160000));
    });

    test('distanceTo is zero for the same point', () {
      const point = LatLng(latitude: 18.6725, longitude: 78.0941);
      expect(point.distanceTo(point), closeTo(0, 1e-6));
    });

    test('isValid rejects out-of-range values, NaN and (0, 0)', () {
      expect(const LatLng(latitude: 91, longitude: 0).isValid, isFalse);
      expect(const LatLng(latitude: 0, longitude: 181).isValid, isFalse);
      expect(const LatLng(latitude: 0, longitude: 0).isValid, isFalse);
      expect(const LatLng(latitude: double.nan, longitude: 78).isValid, isFalse);
      expect(const LatLng(latitude: 18.6725, longitude: 78.0941).isValid, isTrue);
    });
  });

  group('isInServiceArea', () {
    test('Nizamabad is inside India', () {
      expect(isInServiceArea(const LatLng(latitude: 18.6725, longitude: 78.0941)), isTrue);
    });

    test('a device far outside India (for example an emulator default) is rejected', () {
      expect(isInServiceArea(const LatLng(latitude: 37.4219983, longitude: -122.084)), isFalse);
    });

    test('an invalid point is never in the service area', () {
      expect(isInServiceArea(const LatLng(latitude: 0, longitude: 0)), isFalse);
    });
  });
}
