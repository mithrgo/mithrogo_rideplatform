import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/location/lat_lng.dart';
import '../../../core/location/place.dart';
import '../../../shared/widgets/ride_map.dart';
import '../../auth/application/session_controller.dart';
import '../../booking/application/booking_controller.dart';
import '../../booking/application/booking_route_provider.dart';
import '../../notifications/application/notification_providers.dart';
import '../../ride/application/ride_providers.dart';
import '../../ride/models/ride.dart';
import '../../ride/models/ride_options.dart';
import '../application/quick_places_provider.dart';
import 'widgets/booking_sheet.dart';
import 'widgets/discovery_sheet.dart';
import 'widgets/location_banner.dart';

/// Map-first home, like Uber and Rapido. The bottom sheet changes with the booking state:
/// discovery (pick a destination), then booking (route, vehicle, payment, confirm).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(bookingControllerProvider);
    final user = ref.watch(sessionControllerProvider).user;
    final location = ref.watch(currentLocationProvider);
    final current = location.valueOrNull;
    final route = ref.watch(bookingRouteProvider).valueOrNull;
    final activeRide = ref.watch(activeRideProvider).valueOrNull;
    final unread = ref.watch(unreadNotificationCountProvider);

    // Without a chosen pickup, the device position is the pickup.
    final pickup = booking.pickup?.latLng ?? current;
    final drop = booking.drop?.latLng;
    final hasDrop = booking.drop != null;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: RideMap(
              pickup: pickup,
              drop: drop,
              deviceLocation: current,
              route: route,
              onMapTap: (point) => _pickDestination(ref, _pinnedPlace(point)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _PickupPill(
                          label: booking.pickup?.name ?? 'Current location',
                          onTap: () => context.push(AppRoutes.search),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _RoundIconButton(
                        icon: Icons.notifications_none_rounded,
                        tooltip: 'Notifications',
                        badge: unread,
                        onTap: () async {
                          await context.push(AppRoutes.notifications);
                          ref.invalidate(notificationsProvider);
                        },
                      ),
                    ],
                  ),
                  if (location.hasError && booking.pickup == null) ...[
                    const SizedBox(height: 12),
                    LocationBanner(error: location.error!),
                  ],
                  if (activeRide != null) ...[
                    const SizedBox(height: 12),
                    _ActiveRideBanner(
                      ride: activeRide,
                      onTap: () => context.push(AppRoutes.rideDetail(activeRide.id)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: hasDrop
                ? const BookingSheet()
                : DiscoverySheet(
                    firstName: user?.firstName ?? '',
                    onSearchTap: () => context.push(AppRoutes.search),
                    quickPlaces: ref.watch(quickPlacesProvider).valueOrNull ?? const [],
                    onQuickPlaceTap: (place) => _pickDestination(ref, place.toPlace()),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDestination(WidgetRef ref, Place place) {
    return ref.read(bookingControllerProvider.notifier).setDrop(place);
  }

  /// A drop point tapped on the map. Reverse geocoding is not used, so the address is the coordinates.
  static Place _pinnedPlace(LatLng point) {
    final lat = point.latitude.toStringAsFixed(5);
    final lng = point.longitude.toStringAsFixed(5);
    return Place(
      name: 'Pinned location',
      address: 'Pinned on map ($lat, $lng)',
      latitude: point.latitude,
      longitude: point.longitude,
    );
  }
}

class _PickupPill extends StatelessWidget {
  const _PickupPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      elevation: 3,
      shadowColor: Colors.black26,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Badge(
          isLabelVisible: badge > 0,
          backgroundColor: AppColors.danger,
          label: Text(badge > 9 ? '9+' : '$badge'),
          child: Icon(icon, color: AppColors.ink),
        ),
      ),
    );
  }
}

/// Shown while a ride is still going, so the rider can always get back to it.
class _ActiveRideBanner extends StatelessWidget {
  const _ActiveRideBanner({required this.ride, required this.onTap});

  final Ride ride;
  final VoidCallback onTap;

  String get _title => switch (ride.status) {
        RideStatus.accepted => 'Captain is on the way',
        RideStatus.captainArrived => 'Captain has arrived',
        RideStatus.started => 'Ride in progress',
        _ => 'Finding your captain',
      };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ink,
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                child: Icon(
                  ride.vehicleType == VehicleType.auto ? Icons.local_taxi : Icons.two_wheeler,
                  color: AppColors.ink,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(color: AppColors.onInk, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      ride.dropAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Text('View', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w800)),
              const Icon(Icons.chevron_right, color: AppColors.brand),
            ],
          ),
        ),
      ),
    );
  }
}
