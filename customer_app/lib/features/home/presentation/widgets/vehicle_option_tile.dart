import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../ride/models/ride.dart';
import '../../../ride/models/ride_options.dart';

/// One ride option (Bike or Auto) with ETA and fare, like the ride-type rows in Uber and Rapido.
class VehicleOptionTile extends StatelessWidget {
  const VehicleOptionTile({
    super.key,
    required this.vehicle,
    required this.selected,
    required this.onTap,
    this.estimate,
  });

  final VehicleType vehicle;
  final FareEstimate? estimate;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (vehicle) {
        VehicleType.bike => Icons.two_wheeler,
        VehicleType.auto => Icons.local_taxi,
      };

  int get _seats => switch (vehicle) {
        VehicleType.bike => 1,
        VehicleType.auto => 3,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = estimate == null
        ? 'Checking fare...'
        : '${estimate!.durationMinutes} min trip · ${estimate!.distanceKm.toStringAsFixed(1)} km';

    return Material(
      color: selected ? AppColors.brand.withValues(alpha: 0.22) : AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.ink : AppColors.divider,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected ? AppColors.brand : AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon, color: AppColors.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(vehicle.label, style: theme.textTheme.titleMedium),
                        const SizedBox(width: 8),
                        const Icon(Icons.person, size: 16, color: AppColors.ink),
                        const SizedBox(width: 2),
                        Text('$_seats', style: theme.textTheme.bodyMedium),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(detail, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Text(
                estimate == null ? '--' : formatInr(estimate!.fare),
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
