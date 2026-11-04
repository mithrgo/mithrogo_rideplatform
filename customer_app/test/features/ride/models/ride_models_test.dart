import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/ride/models/ride.dart';
import 'package:customer_app/features/ride/models/ride_options.dart';
import 'package:customer_app/features/ride/models/ride_payment.dart';
import 'package:customer_app/features/ride/models/ride_tracking.dart';

void main() {
  group('Ride.fromJson', () {
    test('parses the RideSerializer shape and prefers the final fare', () {
      final ride = Ride.fromJson({
        'id': 'abc',
        'status': 'COMPLETED',
        'vehicle_type': 'AUTO',
        'pickup_address': 'Station Road',
        'drop_address': 'City Mall',
        'estimated_distance_km': '4.20',
        'estimated_duration_minutes': 14,
        'estimated_fare': '62.72',
        'final_fare': '64.00',
        'payment_method': 'ONLINE',
        'requested_at': '2026-10-15T09:05:00Z',
        'captain': {'name': 'Ravi', 'rating': '4.80', 'total_rides': 120},
      });

      expect(ride.status, RideStatus.completed);
      expect(ride.vehicleType, VehicleType.auto);
      expect(ride.estimatedDistanceKm, 4.2);
      expect(ride.captainName, 'Ravi');
      expect(ride.captainRating, 4.8);
      expect(ride.displayFare, '64.00');
      expect(ride.requestedAt, isNotNull);
    });

    test('falls back to the estimate and handles no captain yet', () {
      final ride = Ride.fromJson({
        'id': 'abc',
        'status': 'SEARCHING',
        'vehicle_type': 'BIKE',
        'pickup_address': 'A',
        'drop_address': 'B',
        'estimated_fare': '40.00',
        'final_fare': null,
        'payment_method': 'CASH',
        'captain': null,
      });

      expect(ride.status.isSearching, isTrue);
      expect(ride.displayFare, '40.00');
      expect(ride.captainName, isNull);
    });
  });

  group('RideStatus', () {
    test('unknown codes map to unknown', () {
      expect(RideStatus.fromApi('SOMETHING_NEW'), RideStatus.unknown);
    });

    test('only pre-start rides can be cancelled', () {
      expect(RideStatus.searching.canCancel, isTrue);
      expect(RideStatus.captainArrived.canCancel, isTrue);
      expect(RideStatus.started.canCancel, isFalse);
      expect(RideStatus.completed.isTerminal, isTrue);
    });
  });

  group('RideTracking.fromJson', () {
    test('reads the captain location and vehicle', () {
      final tracking = RideTracking.fromJson({
        'ride_id': 'abc',
        'status': 'ACCEPTED',
        'pickup': {'address': 'A', 'latitude': '18.672500', 'longitude': '73.856700'},
        'drop': {'address': 'B', 'latitude': '18.680000', 'longitude': '73.870000'},
        'captain': {
          'name': 'Ravi',
          'rating': '4.80',
          'latitude': '18.675000',
          'longitude': '73.860000',
          'vehicle': {
            'type': 'BIKE',
            'registration_number': 'MH12AB1234',
            'make': 'Honda',
            'model': 'Activa',
            'color': 'White',
          },
        },
      });

      expect(tracking.status, RideStatus.accepted);
      expect(tracking.pickup.location.latitude, 18.6725);
      expect(tracking.captain?.location?.longitude, 73.86);
      expect(tracking.captain?.vehicle?.description, 'White Honda Activa');
    });

    test('reads the start PIN the backend sends before the trip starts', () {
      final tracking = RideTracking.fromJson({
        'ride_id': 'abc',
        'status': 'CAPTAIN_ARRIVED',
        'pickup': {'address': 'A', 'latitude': '18.6', 'longitude': '73.8'},
        'drop': {'address': 'B', 'latitude': '18.7', 'longitude': '73.9'},
        'captain': {'name': 'Ravi', 'rating': '4.80', 'latitude': '18.6', 'longitude': '73.8'},
        'start_pin': '4821',
      });

      expect(tracking.startPin, '4821');
    });

    test('has no start PIN once the trip has started', () {
      final tracking = RideTracking.fromJson({
        'ride_id': 'abc',
        'status': 'STARTED',
        'pickup': {'address': 'A', 'latitude': '18.6', 'longitude': '73.8'},
        'drop': {'address': 'B', 'latitude': '18.7', 'longitude': '73.9'},
        'captain': null,
        'start_pin': null,
      });

      expect(tracking.startPin, isNull);
    });

    test('has no captain before one accepts', () {
      final tracking = RideTracking.fromJson({
        'ride_id': 'abc',
        'status': 'SEARCHING',
        'pickup': {'address': 'A', 'latitude': '18.6', 'longitude': '73.8'},
        'drop': {'address': 'B', 'latitude': '18.7', 'longitude': '73.9'},
        'captain': null,
      });

      expect(tracking.captain, isNull);
    });
  });

  group('online payment', () {
    Map<String, dynamic> ride(String status, String method, String paymentStatus) => {
          'id': 'r',
          'status': status,
          'payment_method': method,
          'payment_status': paymentStatus,
        };

    test('a completed unpaid ONLINE ride needs payment', () {
      expect(Ride.fromJson(ride('COMPLETED', 'ONLINE', 'UNPAID')).needsOnlinePayment, isTrue);
    });

    test('paid, cash, or unfinished rides do not', () {
      expect(Ride.fromJson(ride('COMPLETED', 'ONLINE', 'PAID')).needsOnlinePayment, isFalse);
      expect(Ride.fromJson(ride('COMPLETED', 'CASH', 'UNPAID')).needsOnlinePayment, isFalse);
      expect(Ride.fromJson(ride('STARTED', 'ONLINE', 'UNPAID')).needsOnlinePayment, isFalse);
    });

    test('RidePayment.fromJson reads the PaymentSerializer shape', () {
      final payment = RidePayment.fromJson({
        'id': 'p-1',
        'amount': '64.00',
        'status': 'PAID',
        'provider_order_id': 'order_123',
      });
      expect(payment.isPaid, isTrue);
      expect(payment.amount, '64.00');
      expect(payment.providerOrderId, 'order_123');
    });
  });
}
