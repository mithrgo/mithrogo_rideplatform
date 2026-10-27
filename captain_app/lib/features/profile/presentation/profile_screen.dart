import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../auth/application/session_controller.dart';
import '../../home/application/home_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../../../shared/widgets/common.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(onboardingProvider).value?.profile;
    final user = ref.watch(sessionControllerProvider).user;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user?.phone ?? profile?.phone ?? '', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Rating ${profile?.rating ?? '-'} · ${profile?.totalRides ?? 0} rides'),
                if (profile != null && profile.licenseNumber.isNotEmpty) Text('Licence ${profile.licenseNumber}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.directions_bike),
            title: const Text('My vehicles'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.vehicles),
          ),
          ListTile(
            leading: const Icon(Icons.workspace_premium),
            title: const Text('Plan and wallet'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.plan),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Sign out',
            danger: true,
            onPressed: () async {
              final home = ref.read(homeControllerProvider).status;
              if (home?.isOnline ?? false) await ref.read(homeControllerProvider.notifier).setOnline(false);
              await ref.read(sessionControllerProvider.notifier).signOut();
            },
          ),
        ],
      ),
    );
  }
}
