import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../kyc/models/captain_profile.dart';
import '../../vehicle/models/vehicle.dart';

/// The next thing a captain has to finish before the home screen.
enum OnboardingGate { kyc, kycReview, vehicle, ready }

class OnboardingState {
  const OnboardingState({required this.profile, required this.vehicles});

  final CaptainProfile profile;
  final List<Vehicle> vehicles;

  OnboardingGate get gate {
    switch (profile.kycStatus) {
      case KycStatus.pending:
      case KycStatus.rejected:
        return OnboardingGate.kyc;
      case KycStatus.underReview:
      case KycStatus.suspended:
        return OnboardingGate.kycReview;
      case KycStatus.approved:
        return vehicles.any((v) => v.isVerified) ? OnboardingGate.ready : OnboardingGate.vehicle;
    }
  }
}

/// Loads the captain's profile and vehicles. The router reads [OnboardingState.gate] to decide
/// which screen to show, so approval by an admin moves the captain on after the next [refresh].
class OnboardingController extends AsyncNotifier<OnboardingState> {
  @override
  Future<OnboardingState> build() => _load();

  Future<OnboardingState> _load() async {
    final profile = await ref.read(kycRepositoryProvider).profile();
    // Vehicles can only be verified after the KYC is approved, so skip the call before that.
    final vehicles =
        profile.kycStatus == KycStatus.approved ? await ref.read(vehicleRepositoryProvider).vehicles() : <Vehicle>[];
    return OnboardingState(profile: profile, vehicles: vehicles);
  }

  /// Reloads without dropping to the loading state, so screens keep showing what they have.
  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }
}

final onboardingProvider = AsyncNotifierProvider<OnboardingController, OnboardingState>(OnboardingController.new);
