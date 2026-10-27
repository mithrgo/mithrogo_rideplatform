import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/common.dart';
import '../../home/application/home_controller.dart';
import '../models/ride.dart';

/// The ride the captain accepted: go to pickup, arrive, start with the rider's PIN, complete,
/// and collect cash. Polls the ride so a cancellation by the rider shows up.
class RideScreen extends ConsumerStatefulWidget {
  const RideScreen({super.key, required this.rideId});

  final String rideId;

  @override
  ConsumerState<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends ConsumerState<RideScreen> {
  Ride? _ride;
  String? _loadError;
  bool _busy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final ride = await ref.read(rideRepositoryProvider).ride(widget.rideId);
      if (mounted) setState(() => _ride = ride);
    } on ApiException catch (error) {
      if (mounted && !silent) setState(() => _loadError = error.message);
    }
  }

  Future<void> _run(Future<Ride> Function(String id) action) async {
    setState(() => _busy = true);
    try {
      final ride = await action(widget.rideId);
      if (mounted) setState(() => _ride = ride);
      await ref.read(homeControllerProvider.notifier).refresh();
    } catch (error) {
      if (mounted) showMessage(context, userMessage(error));
      await _load(silent: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final pin = await _askPin();
    if (pin == null) return;
    await _run((id) => ref.read(rideRepositoryProvider).start(id, pin: pin));
  }

  Future<String?> _askPin() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start ride'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 4,
          autofocus: true,
          decoration: const InputDecoration(labelText: "Rider's 4-digit PIN"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Start')),
        ],
      ),
    );
  }

  Future<void> _cancel() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Why are you cancelling?'),
        children: [
          for (final entry in captainCancelReasons.entries)
            SimpleDialogOption(onPressed: () => Navigator.pop(context, entry.key), child: Text(entry.value)),
        ],
      ),
    );
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(rideRepositoryProvider).cancel(widget.rideId, reason: reason);
      await ref.read(homeControllerProvider.notifier).refresh();
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) showMessage(context, userMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _navigate(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      showMessage(context, 'Could not open maps.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = _ride;
    if (ride == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ride')),
        body: _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : const Center(child: CircularProgressIndicator()),
      );
    }

    final heading = ride.status == 'STARTED' ? 'Drop' : 'Pickup';
    final target = ride.status == 'STARTED' ? (ride.dropLat, ride.dropLng) : (ride.pickupLat, ride.pickupLng);

    return Scaffold(
      appBar: AppBar(title: Text(ride.statusLabel)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatInr(ride.fare), style: Theme.of(context).textTheme.headlineMedium),
                Text('${ride.customerName} · ${ride.distanceKm.toStringAsFixed(1)} km · ${ride.isCash ? 'Cash' : 'Online payment'}'),
                const SizedBox(height: 16),
                _Stop(icon: Icons.trip_origin, color: AppColors.success, label: 'Pickup', address: ride.pickupAddress),
                const SizedBox(height: 10),
                _Stop(icon: Icons.location_on, color: AppColors.danger, label: 'Drop', address: ride.dropAddress),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (ride.isActive)
            OutlinedButton.icon(
              onPressed: () => _navigate(target.$1, target.$2),
              icon: const Icon(Icons.navigation),
              label: Text('Navigate to ${heading.toLowerCase()}'),
            ),
          const SizedBox(height: 16),
          ..._actions(ride),
        ],
      ),
    );
  }

  List<Widget> _actions(Ride ride) {
    final repo = ref.read(rideRepositoryProvider);
    switch (ride.status) {
      case 'ACCEPTED':
        return [
          PrimaryButton(label: "I've arrived", busy: _busy, onPressed: () => _run(repo.arrived)),
          const SizedBox(height: 12),
          TextButton(onPressed: _busy ? null : _cancel, child: const Text('Cancel ride')),
        ];
      case 'CAPTAIN_ARRIVED':
        return [
          PrimaryButton(label: 'Start ride', busy: _busy, onPressed: _start),
          const SizedBox(height: 12),
          TextButton(onPressed: _busy ? null : _cancel, child: const Text('Cancel ride')),
        ];
      case 'STARTED':
        return [PrimaryButton(label: 'Complete ride', busy: _busy, onPressed: () => _run(repo.complete))];
      case 'COMPLETED':
        return [
          if (ride.isCash && ride.paymentStatus != 'PAID')
            PrimaryButton(label: 'Cash collected', busy: _busy, onPressed: () => _run(repo.collectCash))
          else
            const InfoCard(child: Text('Ride completed. Earnings are updated.')),
          const SizedBox(height: 12),
          TextButton(onPressed: () => context.pop(), child: const Text('Back to home')),
        ];
      default:
        return [
          const InfoCard(child: Text('This ride was cancelled.')),
          const SizedBox(height: 12),
          TextButton(onPressed: () => context.pop(), child: const Text('Back to home')),
        ];
    }
  }
}

class _Stop extends StatelessWidget {
  const _Stop({required this.icon, required this.color, required this.label, required this.address});

  final IconData icon;
  final Color color;
  final String label;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(address),
            ],
          ),
        ),
      ],
    );
  }
}
