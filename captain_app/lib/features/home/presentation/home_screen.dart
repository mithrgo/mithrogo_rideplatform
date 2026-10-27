import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/common.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../../vehicle/models/vehicle.dart';
import '../application/home_controller.dart';
import '../models/home_models.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeControllerProvider);
    final status = home.status;

    return Scaffold(
      appBar: AppBar(title: const Text('MithrGo Captain')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(homeControllerProvider.notifier).refresh(),
        child: home.loading
            ? const Center(child: CircularProgressIndicator())
            : status == null
                ? ErrorView(
                    message: home.error ?? 'Could not load your status.',
                    onRetry: () => ref.read(homeControllerProvider.notifier).refresh(),
                  )
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _OnlineCard(status: status),
                      const SizedBox(height: 16),
                      if (home.activeRide != null) ...[
                        InfoCard(
                          color: AppColors.brand.withValues(alpha: 0.25),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('You have a ride in progress'),
                                    Text(home.activeRide!.statusLabel, style: Theme.of(context).textTheme.titleMedium),
                                  ],
                                ),
                              ),
                              FilledButton(
                                onPressed: () => context.push('/ride/${home.activeRide!.id}'),
                                child: const Text('Open'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      for (final offer in home.offers)
                        if (home.activeRide == null) _OfferCard(offer: offer),
                      if (!status.eligible && !status.isOnline) _Requirements(status: status),
                      if (status.isOnline && home.offers.isEmpty && home.activeRide == null)
                        const InfoCard(child: Text('You are online. Waiting for ride requests…')),
                    ],
                  ),
      ),
    );
  }
}

class _OnlineCard extends ConsumerStatefulWidget {
  const _OnlineCard({required this.status});

  final CaptainStatusInfo status;

  @override
  ConsumerState<_OnlineCard> createState() => _OnlineCardState();
}

class _OnlineCardState extends ConsumerState<_OnlineCard> {
  bool _busy = false;

  Future<void> _toggle(bool online) async {
    setState(() => _busy = true);
    final error = await ref.read(homeControllerProvider.notifier).setOnline(online);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) showMessage(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final canToggle = !_busy && !status.isBusy && (status.isOnline || status.eligible);

    return InfoCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.isBusy ? 'On a ride' : (status.isOnline ? 'You are online' : 'You are offline'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (status.todayVehicleType != null) Text('Today: ${vehicleTypeLabel(status.todayVehicleType)}'),
              ],
            ),
          ),
          Switch(value: status.isOnline, onChanged: canToggle ? _toggle : null),
        ],
      ),
    );
  }
}

/// Why the captain cannot go online yet, with a button for each thing they can fix.
class _Requirements extends ConsumerWidget {
  const _Requirements({required this.status});

  final CaptainStatusInfo status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicles = (ref.watch(onboardingProvider).value?.vehicles ?? const <Vehicle>[]).where((v) => v.isVerified);
    final needsVehicle = status.needs('vehicle_not_selected');
    final needsPlan = status.reasons.any(
      (r) => const {'no_active_plan', 'plan_expired', 'plan_vehicle_mismatch', 'shortfall_fee_unpaid'}.contains(r),
    );
    final hasDues = status.needs('dues_over_limit');

    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Before you go online', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(status.message),
          if (needsVehicle) ...[
            const SizedBox(height: 16),
            const Text("Today's vehicle"),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final v in vehicles)
                  ActionChip(
                    label: Text('${v.typeLabel} · ${v.registrationNumber}'),
                    onPressed: () async {
                      final error = await ref.read(homeControllerProvider.notifier).chooseVehicle(v.type);
                      if (error != null && context.mounted) showMessage(context, error);
                    },
                  ),
              ],
            ),
          ],
          if (needsPlan) ...[
            const SizedBox(height: 16),
            PrimaryButton(label: 'Choose a plan', onPressed: () => context.push(AppRoutes.plan)),
          ],
          if (hasDues) ...[
            const SizedBox(height: 16),
            PrimaryButton(label: 'Pay dues', onPressed: () => context.go(AppRoutes.earnings)),
          ],
        ],
      ),
    );
  }
}

class _OfferCard extends ConsumerStatefulWidget {
  const _OfferCard({required this.offer});

  final RideOffer offer;

  @override
  ConsumerState<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends ConsumerState<_OfferCard> {
  Timer? _ticker;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Redraws the countdown once a second.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    final error = await ref.read(homeControllerProvider.notifier).accept(widget.offer);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      showMessage(context, error);
    } else {
      context.push('/ride/${widget.offer.rideId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final seconds = offer.secondsLeft;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InfoCard(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('New ride request', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                StatusChip(label: '${seconds}s', color: seconds <= 5 ? AppColors.danger : AppColors.info),
              ],
            ),
            const SizedBox(height: 12),
            Text(formatInr(offer.fare), style: Theme.of(context).textTheme.headlineMedium),
            Text('${offer.distanceKm.toStringAsFixed(1)} km away'),
            const SizedBox(height: 12),
            _AddressRow(icon: Icons.trip_origin, color: AppColors.success, text: offer.pickupAddress),
            const SizedBox(height: 6),
            _AddressRow(icon: Icons.location_on, color: AppColors.danger, text: offer.dropAddress),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => ref.read(homeControllerProvider.notifier).reject(offer),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: PrimaryButton(label: 'Accept', busy: _busy, onPressed: seconds > 0 ? _accept : null)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}
