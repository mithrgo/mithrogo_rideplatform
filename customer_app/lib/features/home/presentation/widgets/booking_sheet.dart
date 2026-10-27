import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../booking/application/booking_controller.dart';
import '../../../booking/application/booking_route_provider.dart';
import '../../../ride/application/ride_providers.dart';
import '../../../ride/models/ride_options.dart';
import '../../../../shared/widgets/sheet_container.dart';
import 'vehicle_option_tile.dart';

/// Shown once a destination is chosen: route, ride options, payment, and the book button.
class BookingSheet extends ConsumerStatefulWidget {
  const BookingSheet({super.key});

  @override
  ConsumerState<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends ConsumerState<BookingSheet> {
  bool _booking = false;

  Future<void> _book() async {
    setState(() => _booking = true);
    try {
      final rideId = await ref.read(bookingControllerProvider.notifier).book();
      ref.invalidate(rideHistoryProvider);
      if (!mounted) return;
      context.go(AppRoutes.rideDetail(rideId));
    } on ApiException catch (error) {
      if (error.code == 'active_ride_exists') {
        await _openActiveRide();
      } else {
        _showMessage(error.message);
      }
    } catch (error) {
      _showMessage(userMessage(error));
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  /// The backend allows one active ride per customer. Take them to it instead of a dead end.
  Future<void> _openActiveRide() async {
    ref.invalidate(rideHistoryProvider);
    final active = await ref.read(activeRideProvider.future).catchError((_) => null);
    if (!mounted) return;
    if (active == null) {
      _showMessage('You already have a ride in progress.');
      return;
    }
    _showMessage('You already have a ride in progress.');
    context.go(AppRoutes.rideDetail(active.id));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final booking = ref.watch(bookingControllerProvider);
    final notifier = ref.read(bookingControllerProvider.notifier);
    final selected = booking.selectedEstimate;

    return SheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RouteCard(
            pickup: booking.pickup?.name ?? 'Current location',
            drop: booking.drop?.name ?? '',
            onChange: () => context.push(AppRoutes.search),
            onClear: notifier.clearDrop,
          ),
          const SizedBox(height: 8),
          const _RouteSummary(),
          const SizedBox(height: 16),
          Text('Choose a ride', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final vehicle in VehicleType.values) ...[
            VehicleOptionTile(
              vehicle: vehicle,
              estimate: booking.estimates[vehicle],
              selected: booking.vehicle == vehicle,
              onTap: () => notifier.selectVehicle(vehicle),
            ),
            const SizedBox(height: 8),
          ],
          if (booking.estimating) ...[
            const SizedBox(height: 4),
            const LinearProgressIndicator(minHeight: 2, color: AppColors.ink),
            const SizedBox(height: 8),
          ],
          if (booking.error != null) ...[
            Row(
              children: [
                Expanded(child: Text(booking.error!, style: const TextStyle(color: AppColors.danger))),
                TextButton(onPressed: notifier.retryEstimates, child: const Text('Retry')),
              ],
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          Text('Add a tip for your captain', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _TipSelector(tip: booking.tip, onChanged: notifier.setTip),
          const SizedBox(height: 12),
          // Cash only for now; UPI / card will come later.
          Row(
            children: [
              const Icon(Icons.payments_outlined, size: 20),
              const SizedBox(width: 8),
              Text('Pay with cash', style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 16),
          AppButton(
            variant: AppButtonVariant.brand,
            label: selected == null
                ? 'Book ${booking.vehicle.label}'
                : 'Book ${booking.vehicle.label} · ${formatRupees((roundToRupees(selected.fare) + BigInt.from(booking.tip)).toInt())}',
            loading: _booking,
            onPressed: booking.canBook && !_booking ? _book : null,
          ),
        ],
      ),
    );
  }
}

/// Driving distance and time from OSRM. The time is an estimate, not a live-traffic ETA.
class _RouteSummary extends ConsumerWidget {
  const _RouteSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final route = ref.watch(bookingRouteProvider);

    return route.when(
      loading: () => Row(
        children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text('Finding the driving route…', style: theme.textTheme.bodySmall),
        ],
      ),
      error: (error, _) => Row(
        children: [
          Expanded(
            child: Text(
              userMessage(error),
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
          TextButton(
            onPressed: () => ref.invalidate(bookingRouteProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
      data: (result) {
        if (result == null) return const SizedBox.shrink();
        return Text(
          '${result.distanceLabel} · about ${result.durationLabel} (estimate)',
          style: theme.textTheme.bodySmall,
        );
      },
    );
  }
}

class _TipSelector extends StatelessWidget {
  const _TipSelector({required this.tip, required this.onChanged});

  static const _presets = [20, 30, 50];

  final int tip;
  final ValueChanged<int> onChanged;

  bool get _isCustom => tip > 0 && !_presets.contains(tip);

  Future<void> _askCustom(BuildContext context) async {
    final controller = TextEditingController(text: _isCustom ? '$tip' : '');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom tip'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          decoration: const InputDecoration(prefixText: '₹ ', hintText: 'Amount'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text) ?? 0),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final amount in _presets)
          ChoiceChip(
            label: Text('₹$amount'),
            selected: tip == amount,
            // Tapping the selected amount again removes the tip.
            onSelected: (selected) => onChanged(selected ? amount : 0),
          ),
        ChoiceChip(
          label: Text(_isCustom ? '₹$tip' : 'Custom'),
          selected: _isCustom,
          onSelected: (_) => _askCustom(context),
        ),
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.pickup,
    required this.drop,
    required this.onChange,
    required this.onClear,
  });

  final String pickup;
  final String drop;
  final VoidCallback onChange;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
              ),
              Container(width: 2, height: 22, color: AppColors.divider),
              Container(width: 10, height: 10, color: AppColors.ink),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pickup, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                const SizedBox(height: 10),
                Text(
                  drop,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onChange, child: const Text('Change')),
          IconButton(
            tooltip: 'Clear destination',
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }
}
