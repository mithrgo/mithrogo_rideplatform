import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../auth/application/session_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../models/captain_profile.dart';

/// Shown while an admin reviews the documents (or after the account was suspended).
/// Checks the status every few seconds; the router moves on once an admin approves.
class KycReviewScreen extends ConsumerStatefulWidget {
  const KycReviewScreen({super.key});

  @override
  ConsumerState<KycReviewScreen> createState() => _KycReviewScreenState();
}

class _KycReviewScreenState extends ConsumerState<KycReviewScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => ref.read(onboardingProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suspended = ref.watch(onboardingProvider).value?.profile.kycStatus == KycStatus.suspended;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(suspended ? Icons.block : Icons.hourglass_top, size: 64, color: AppColors.brandDark),
              const SizedBox(height: 20),
              Text(
                suspended ? 'Account suspended' : 'Documents under review',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                suspended
                    ? 'Your account has been suspended. Please contact support.'
                    : 'Our team is checking your documents. This screen updates by itself once you are approved.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              OutlinedButton(
                onPressed: () => ref.read(onboardingProvider.notifier).refresh(),
                child: const Text('Check status'),
              ),
              TextButton(
                onPressed: () => ref.read(sessionControllerProvider.notifier).signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
