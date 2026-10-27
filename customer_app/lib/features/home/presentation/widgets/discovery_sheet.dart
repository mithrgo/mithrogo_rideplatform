import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../models/quick_place.dart';
import '../../../../shared/widgets/sheet_container.dart';

IconData _iconFor(String key) => switch (key) {
      'train' => Icons.train,
      'bus' => Icons.directions_bus,
      'mall' => Icons.local_mall,
      'hospital' => Icons.local_hospital,
      'temple' => Icons.temple_hindu,
      'school' => Icons.school,
      'airport' => Icons.flight,
      'restaurant' => Icons.restaurant,
      'park' => Icons.park,
      'office' => Icons.business,
      _ => Icons.place,
    };

/// Shown before a destination is chosen: greeting, the search entry point and popular destinations.
class DiscoverySheet extends StatelessWidget {
  const DiscoverySheet({
    super.key,
    required this.firstName,
    required this.onSearchTap,
    required this.quickPlaces,
    required this.onQuickPlaceTap,
  });

  final String firstName;
  final VoidCallback onSearchTap;
  final List<QuickPlace> quickPlaces;
  final ValueChanged<QuickPlace> onQuickPlaceTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            firstName.isEmpty ? 'Where to?' : 'Hi $firstName, where to?',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onSearchTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppColors.ink),
                  const SizedBox(width: 12),
                  Text('Search destination', style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                      )),
                ],
              ),
            ),
          ),
          if (quickPlaces.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final place in quickPlaces)
                  _QuickPlaceCard(place: place, onTap: () => onQuickPlaceTap(place)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Tip: tap the map to drop a pin instead.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _QuickPlaceCard extends StatelessWidget {
  const _QuickPlaceCard({required this.place, required this.onTap});

  final QuickPlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                child: Icon(_iconFor(place.icon), size: 18, color: AppColors.ink),
              ),
              const SizedBox(width: 8),
              Text(place.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
