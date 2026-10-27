import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/location/location_service.dart';
import '../core/network/api_client.dart';
import '../core/storage/token_storage.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/earnings/data/earnings_repository.dart';
import '../features/home/data/home_repository.dart';
import '../features/kyc/data/kyc_repository.dart';
import '../features/plan/data/plan_repository.dart';
import '../features/ride/data/ride_repository.dart';
import '../features/vehicle/data/vehicle_repository.dart';

/// Composition root: providers shared across features.

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    tokenStorage: ref.watch(tokenStorageProvider),
    // Read lazily, so building the client never touches the session controller.
    onSessionExpired: () => ref.read(sessionControllerProvider.notifier).expire(),
  );
});

final authRepositoryProvider = Provider((ref) => AuthRepository(ref.watch(apiClientProvider)));

final kycRepositoryProvider = Provider((ref) => KycRepository(ref.watch(apiClientProvider)));

final vehicleRepositoryProvider = Provider((ref) => VehicleRepository(ref.watch(apiClientProvider)));

final homeRepositoryProvider = Provider((ref) => HomeRepository(ref.watch(apiClientProvider)));

final rideRepositoryProvider = Provider((ref) => RideRepository(ref.watch(apiClientProvider)));

final earningsRepositoryProvider = Provider((ref) => EarningsRepository(ref.watch(apiClientProvider)));

final planRepositoryProvider = Provider((ref) => PlanRepository(ref.watch(apiClientProvider)));
