import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/application/session_controller.dart';
import '../../home/application/home_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../../../shared/widgets/common.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text('Your details and documents will be removed. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      // The server has ended the session; clear the local tokens too, so the router moves to sign-in.
      await ref.read(sessionControllerProvider.notifier).expire();
    } catch (error) {
      if (context.mounted) showMessage(context, userMessage(error));
    }
  }

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
          TextButton(
            onPressed: () => _deleteAccount(context, ref),
            child: const Text('Delete account', style: TextStyle(color: AppColors.danger)),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Sign out',
            danger: true,
            onPressed: () async {
              final home = ref.read(homeControllerProvider).status;
              if (home?.isBusy ?? false) {
                showMessage(context, 'Finish your current ride before signing out.');
                return;
              }
              if (home?.isOnline ?? false) await ref.read(homeControllerProvider.notifier).setOnline(false);
              await ref.read(sessionControllerProvider.notifier).signOut();
            },
          ),
        ],
      ),
    );
  }
}
