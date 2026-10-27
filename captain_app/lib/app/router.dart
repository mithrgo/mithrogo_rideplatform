import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/session_controller.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/otp_screen.dart';
import '../features/earnings/presentation/earnings_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/kyc/presentation/kyc_review_screen.dart';
import '../features/kyc/presentation/kyc_screen.dart';
import '../features/onboarding/application/onboarding_controller.dart';
import '../features/plan/presentation/plan_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/ride/presentation/history_screen.dart';
import '../features/ride/presentation/ride_screen.dart';
import '../features/splash/presentation/splash_screen.dart';
import '../features/vehicle/presentation/vehicle_screen.dart';
import 'app_shell.dart';

abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const otp = '/otp';
  static const kyc = '/kyc';
  static const kycReview = '/kyc/review';
  static const onboardingVehicle = '/onboarding/vehicle';
  static const home = '/home';
  static const earnings = '/earnings';
  static const history = '/history';
  static const profile = '/profile';
  static const plan = '/plan';
  static const vehicles = '/vehicles';
}

/// Tells the router to re-run its redirect when sign-in or onboarding state changes.
class _RouterRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.listen(sessionControllerProvider, (_, _) => refresh.ping());
  ref.listen(onboardingProvider, (_, _) => refresh.ping());
  ref.onDispose(refresh.dispose);

  String? redirect(String location) {
    final session = ref.read(sessionControllerProvider);

    if (session.status == SessionStatus.unknown) return location == AppRoutes.splash ? null : AppRoutes.splash;

    if (session.status == SessionStatus.signedOut) {
      return location == AppRoutes.login || location == AppRoutes.otp ? null : AppRoutes.login;
    }

    // Signed in: wait for the captain's KYC and vehicle state, then send them to the right step.
    final onboarding = ref.read(onboardingProvider);
    final state = onboarding.value;
    if (state == null) return location == AppRoutes.splash ? null : AppRoutes.splash;

    final target = switch (state.gate) {
      OnboardingGate.kyc => AppRoutes.kyc,
      OnboardingGate.kycReview => AppRoutes.kycReview,
      OnboardingGate.vehicle => AppRoutes.onboardingVehicle,
      OnboardingGate.ready => null,
    };
    if (target != null) return location == target ? null : target;

    const onboardingOnly = {
      AppRoutes.splash,
      AppRoutes.login,
      AppRoutes.otp,
      AppRoutes.kyc,
      AppRoutes.kycReview,
      AppRoutes.onboardingVehicle,
    };
    return onboardingOnly.contains(location) ? AppRoutes.home : null;
  }

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (_, state) => redirect(state.matchedLocation),
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: AppRoutes.otp, builder: (_, state) => OtpScreen(phone: state.extra as String? ?? '')),
      GoRoute(path: AppRoutes.kyc, builder: (_, _) => const KycScreen()),
      GoRoute(path: AppRoutes.kycReview, builder: (_, _) => const KycReviewScreen()),
      GoRoute(path: AppRoutes.onboardingVehicle, builder: (_, _) => const VehicleScreen(onboarding: true)),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.home, builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.earnings, builder: (_, _) => const EarningsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.history, builder: (_, _) => const HistoryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.profile, builder: (_, _) => const ProfileScreen())]),
        ],
      ),
      GoRoute(path: '/ride/:id', builder: (_, state) => RideScreen(rideId: state.pathParameters['id']!)),
      GoRoute(path: AppRoutes.plan, builder: (_, _) => const PlanScreen()),
      GoRoute(path: AppRoutes.vehicles, builder: (_, _) => const VehicleScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
