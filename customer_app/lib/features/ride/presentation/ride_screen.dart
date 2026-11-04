import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/map_canvas.dart';
import '../../../shared/widgets/sheet_container.dart';
import '../application/ride_providers.dart';
import '../models/ride.dart';
import '../models/ride_tracking.dart';
import 'widgets/captain_card.dart';
import 'widgets/completed_sheet.dart';

/// Live view of one ride. The bottom sheet follows the status:
/// searching, captain on the way, arrived, in progress, completed, or cancelled.
class RideScreen extends ConsumerWidget {
  const RideScreen({super.key, required this.rideId});

  final String rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rideTrackingProvider(rideId));
    final tracking = async.valueOrNull;
    final status = tracking?.status ?? RideStatus.unknown;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: MapCanvas(
              pickup: tracking?.pickup.location,
              drop: tracking?.drop.location,
              captain: tracking?.captain?.location,
              showPulse: status.isSearching,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Material(
                    color: AppColors.card,
                    elevation: 3,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Home',
                      onPressed: () => _leave(context, ref),
                      icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                    ),
                  ),
                  const Spacer(),
                  if (tracking != null && !status.isTerminal)
                    Material(
                      color: AppColors.danger,
                      elevation: 3,
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => context.push(AppRoutes.emergency),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.sos_rounded, color: AppColors.onInk, size: 20),
                              SizedBox(width: 6),
                              Text('SOS', style: TextStyle(color: AppColors.onInk, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildSheet(context, ref, async, tracking),
          ),
        ],
      ),
    );
  }

  Widget _buildSheet(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<RideTracking> async,
    RideTracking? tracking,
  ) {
    if (tracking == null) {
      if (async.hasError) {
        return _ErrorSheet(
          message: userMessage(async.error!),
          onRetry: () => ref.invalidate(rideTrackingProvider(rideId)),
        );
      }
      return const _LoadingSheet();
    }

    final status = tracking.status;
    final captain = tracking.captain;
    if (status.isSearching) {
      return _SearchingSheet(onCancel: () => _cancel(context, ref));
    }
    if (status == RideStatus.completed) {
      return CompletedSheet(rideId: rideId);
    }
    if (status == RideStatus.cancelled) {
      return SheetContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ride cancelled', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(
              'No charges were made for this ride. You can book again any time.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            AppButton(label: 'Book another ride', onPressed: () => context.go(AppRoutes.home)),
          ],
        ),
      );
    }

    // Captain assigned: accepted, arrived, or started.
    final title = switch (status) {
      RideStatus.accepted => 'Captain is on the way',
      RideStatus.captainArrived => 'Captain has arrived',
      RideStatus.started => 'On the way to your drop',
      _ => 'Connecting you',
    };
    return SheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            tracking.drop.address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (captain != null) CaptainCard(captain: captain, startPin: tracking.startPin),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  variant: AppButtonVariant.outline,
                  label: 'Help',
                  icon: Icons.support_agent_outlined,
                  onPressed: () => context.push(AppRoutes.support, extra: rideId),
                ),
              ),
              if (status != RideStatus.started && status.canCancel) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    variant: AppButtonVariant.outline,
                    label: 'Cancel',
                    onPressed: () => _cancel(context, ref),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Back to where the ride was opened from (history, notifications), or home.
  void _leave(BuildContext context, WidgetRef ref) {
    ref.invalidate(rideHistoryProvider);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this ride?'),
        content: const Text('You can book again any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep ride')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel ride')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(rideRepositoryProvider).cancel(rideId);
      // Re-run tracking so the screen shows the cancelled state at once.
      ref.invalidate(rideTrackingProvider(rideId));
      ref.invalidate(rideHistoryProvider);
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _SearchingSheet extends StatelessWidget {
  const _SearchingSheet({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Finding your captain', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text('Matching you with nearby captains.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 14),
          const LinearProgressIndicator(minHeight: 3, color: AppColors.ink),
          const SizedBox(height: 18),
          AppButton(
            variant: AppButtonVariant.outline,
            label: 'Cancel ride',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _LoadingSheet extends StatelessWidget {
  const _LoadingSheet();

  @override
  Widget build(BuildContext context) {
    return const SheetContainer(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(color: AppColors.ink)),
      ),
    );
  }
}

class _ErrorSheet extends StatelessWidget {
  const _ErrorSheet({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          AppButton(label: 'Try again', onPressed: onRetry),
        ],
      ),
    );
  }
}
