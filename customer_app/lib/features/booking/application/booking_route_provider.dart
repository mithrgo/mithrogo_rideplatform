import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/location/lat_lng.dart';
import '../../../core/routing/route_service.dart';
import 'booking_controller.dart';

/// Driving route from the pickup to the drop. Null until a drop is chosen.
///
/// Recalculated only when the pickup or drop point changes. Map pan and zoom never touch it.
/// Riverpod drops the result of a superseded request, so an old route cannot replace a newer one.
final bookingRouteProvider = FutureProvider.autoDispose<RouteResult?>((ref) async {
  final drop = ref.watch(bookingControllerProvider.select((state) => state.drop));
  if (drop == null) return null;

  final pickup = ref.watch(bookingControllerProvider.select((state) => state.pickup));
  final LatLng origin;
  if (pickup != null) {
    origin = pickup.latLng;
  } else {
    origin = await ref.watch(currentLocationProvider.future);
  }

  return ref.watch(routeServiceProvider).route(from: origin, to: drop.latLng);
});
