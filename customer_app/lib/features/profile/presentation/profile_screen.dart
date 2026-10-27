import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../auth/application/session_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final session = ref.read(sessionControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final blockers = await session.deletionBlockers();
      if (!context.mounted) return;
      if (blockers.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cannot delete yet'),
            content: Text(blockers.join('\n\n')),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete account?'),
          content: const Text(
            'Your account and personal details will be permanently deleted. This cannot be undone.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await session.deleteAccount();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(userMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(customerProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: profileAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: userMessage(error),
          onRetry: () => ref.invalidate(customerProfileProvider),
        ),
        data: (profile) {
          final initial = profile.firstName.isEmpty ? '?' : profile.firstName[0].toUpperCase();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header card, ink with a yellow avatar, like the account screens in Uber and Rapido.
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColors.brand,
                      child: Text(
                        initial,
                        style: const TextStyle(color: AppColors.ink, fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.fullName.isEmpty ? 'Add your name' : profile.fullName,
                            style: const TextStyle(
                              color: AppColors.onInk,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            profile.phone,
                            style: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit profile',
                      onPressed: () => context.push(AppRoutes.editProfile),
                      icon: const Icon(Icons.edit_outlined, color: AppColors.brand),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _MenuSection(
                items: [
                  _MenuItem(
                    icon: Icons.history,
                    label: 'Your rides',
                    onTap: () => context.go(AppRoutes.history),
                  ),
                  _MenuItem(
                    icon: Icons.health_and_safety_outlined,
                    label: 'Safety centre',
                    onTap: () => context.push(AppRoutes.emergency),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _MenuSection(
                items: [
                  _MenuItem(
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    onTap: () => context.push(AppRoutes.notifications),
                  ),
                  _MenuItem(
                    icon: Icons.support_agent_outlined,
                    label: 'Help and support',
                    onTap: () => context.push(AppRoutes.support),
                  ),
                  _MenuItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () => context.push(AppRoutes.settings),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () => _deleteAccount(context, ref),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete account'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MenuSection extends StatelessWidget {
  const _MenuSection({required this.items});

  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            items[i],
          ],
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.ink),
      title: Text(label, style: Theme.of(context).textTheme.bodyLarge),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}
