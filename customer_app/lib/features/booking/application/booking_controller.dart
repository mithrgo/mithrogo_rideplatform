import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/location/place.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/routing/ride_distance_policy.dart';
import '../../ride/models/ride.dart';
import '../../ride/models/ride_options.dart';

/// The ride being planned on the home screen, before it is booked.
class BookingState {
  const BookingState({
    this.pickup,
    this.drop,
    this.vehicle = VehicleType.bike,
    this.payment = PaymentMethod.cash,
    this.estimates = const {},
    this.estimating = false,
    this.error,
    this.tip = 0,
  });

  /// Null means "current location", resolved when needed.
  final Place? pickup;
  final Place? drop;
  final VehicleType vehicle;
  final PaymentMethod payment;
  final Map<VehicleType, FareEstimate> estimates;
  final bool estimating;
  final String? error;

  /// Optional tip in whole rupees, 0 for none.
  final int tip;

  FareEstimate? get selectedEstimate => estimates[vehicle];

  bool get canBook => drop != null && selectedEstimate != null && !estimating;

  BookingState copyWith({
    Place? pickup,
    Place? drop,
    VehicleType? vehicle,
    PaymentMethod? payment,
    Map<VehicleType, FareEstimate>? estimates,
    bool? estimating,
    String? error,
    int? tip,
    bool clearError = false,
  }) {
    return BookingState(
      pickup: pickup ?? this.pickup,
      drop: drop ?? this.drop,
      vehicle: vehicle ?? this.vehicle,
      payment: payment ?? this.payment,
      estimates: estimates ?? this.estimates,
      estimating: estimating ?? this.estimating,
      error: clearError ? null : (error ?? this.error),
      tip: tip ?? this.tip,
    );
  }
}

class BookingController extends Notifier<BookingState> {
  @override
  BookingState build() => const BookingState();

  // Bumped on every estimate request, so a slow response for an old route is ignored.
  int _estimateRequest = 0;

  Future<void> setDrop(Place place) async {
    state = state.copyWith(drop: place, estimates: const {}, clearError: true);
    await _loadEstimates();
  }

  Future<void> setPickup(Place place) async {
    state = state.copyWith(pickup: place, estimates: const {}, clearError: true);
    await _loadEstimates();
  }

  /// Back to the device's current location as the pickup.
  Future<void> useCurrentLocationForPickup() async {
    state = BookingState(
      drop: state.drop,
      vehicle: state.vehicle,
      payment: state.payment,
    );
    await _loadEstimates();
  }

  Future<void> retryEstimates() => _loadEstimates();

  void selectVehicle(VehicleType vehicle) {
    state = state.copyWith(vehicle: vehicle);
  }

  void selectPayment(PaymentMethod payment) {
    state = state.copyWith(payment: payment);
  }

  void setTip(int tip) {
    state = state.copyWith(tip: tip < 0 ? 0 : tip);
  }

  void clearDrop() {
    _estimateRequest++;
    state = BookingState(
      pickup: state.pickup,
      vehicle: state.vehicle,
      payment: state.payment,
    );
  }

  /// Creates the ride and returns its id. The planning state is reset afterwards.
  Future<String> book() async {
    final drop = state.drop;
    if (drop == null) {
      throw StateError('Choose a drop location first.');
    }
    final pickup = await _origin();
    await _ensureWithinRideLimit(pickup, drop);
    // The booker must be in the service area even when the pickup is a friend's address.
    final device = await ref.read(currentLocationProvider.future);
    final ride = await ref.read(rideRepositoryProvider).create(
          pickup: pickup,
          drop: drop,
          vehicleType: state.vehicle,
          paymentMethod: state.payment,
          tip: state.tip,
          deviceLocation: device,
          idempotencyKey: DateTime.now().microsecondsSinceEpoch.toString(),
        );
    clearDrop();
    return ride.id;
  }

  Future<void> _loadEstimates() async {
    final drop = state.drop;
    if (drop == null) return;

    final request = ++_estimateRequest;
    state = state.copyWith(estimating: true, clearError: true);
    try {
      final origin = await _origin();
      // Over-limit or unroutable trips never reach the fare endpoint.
      await _ensureWithinRideLimit(origin, drop);
      final repository = ref.read(rideRepositoryProvider);
      final results = await Future.wait(VehicleType.values.map((vehicle) => repository.estimate(
            vehicleType: vehicle,
            pickup: origin,
            drop: drop,
          )));
      // The rider may have changed the route while this was loading.
      if (request != _estimateRequest) return;
      state = state.copyWith(
        estimates: {for (final estimate in results) estimate.vehicleType: estimate},
        estimating: false,
      );
    } catch (error) {
      if (request != _estimateRequest) return;
      state = state.copyWith(estimating: false, error: userMessage(error));
    }
  }

  /// Checks the driving distance from the pickup to the drop against the ride limit.
  Future<void> _ensureWithinRideLimit(Place origin, Place drop) async {
    final route = await ref.read(routeServiceProvider).route(from: origin.latLng, to: drop.latLng);
    ensureWithinRideLimit(route.distanceMeters);
  }

  Future<Place> _origin() async {
    final pickup = state.pickup;
    if (pickup != null) return pickup;

    final location = await ref.read(currentLocationProvider.future);
    return Place(
      name: 'Current location',
      address: 'Current location',
      latitude: location.latitude,
      longitude: location.longitude,
    );
  }
}

final bookingControllerProvider = NotifierProvider<BookingController, BookingState>(
  BookingController.new,
);
