import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/geocoding/nearby_feature_service.dart';
import '../core/geocoding/place_search_service.dart';
import '../core/location/lat_lng.dart';
import '../core/location/location_service.dart';
import '../core/network/api_client.dart';
import '../core/routing/route_service.dart';
import '../core/storage/token_storage.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/notifications/data/notification_repository.dart';
import '../features/profile/data/profile_repository.dart';
import '../features/profile/models/customer_profile.dart';
import '../features/ride/data/ride_repository.dart';
import '../features/support/data/support_repository.dart';

/// Composition root: providers shared across features.

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    tokenStorage: ref.watch(tokenStorageProvider),
    // Read lazily, so building the client never touches the session controller.
    onSessionExpired: () => ref.read(sessionControllerProvider.notifier).expire(),
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(apiClientProvider));
});

final rideRepositoryProvider = Provider<RideRepository>((ref) {
  return RideRepository(ref.watch(apiClientProvider));
});

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(apiClientProvider));
});

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return SupportRepository(ref.watch(apiClientProvider));
});

final customerProfileProvider = FutureProvider.autoDispose<CustomerProfile>((ref) {
  return ref.watch(profileRepositoryProvider).fetch();
});

final locationServiceProvider = Provider<LocationService>((ref) => GeolocatorLocationService());

final currentLocationProvider = FutureProvider.autoDispose<LatLng>((ref) {
  return ref.watch(locationServiceProvider).currentLocation();
});

final routeServiceProvider = Provider<RouteService>((ref) {
  final service = OsrmRouteService();
  ref.onDispose(service.close);
  return service;
});

final placeSearchServiceProvider = Provider<PlaceSearchService>((ref) {
  final service = NominatimPlaceSearchService();
  ref.onDispose(service.close);
  return service;
});

final nearbyFeatureServiceProvider = Provider<NearbyFeatureService>((ref) {
  final service = OverpassNearbyFeatureService();
  ref.onDispose(service.close);
  return service;
});
