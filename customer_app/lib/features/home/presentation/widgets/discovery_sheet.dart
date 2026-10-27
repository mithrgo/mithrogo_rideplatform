import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/sheet_container.dart';

/// Shown before a destination is chosen: greeting and the search entry point.
/// Destinations come from a live search, so there is no fixed list here.
class DiscoverySheet extends StatelessWidget {
  const DiscoverySheet({
    super.key,
    required this.firstName,
    required this.onSearchTap,
  });

  final String firstName;
  final VoidCallback onSearchTap;

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
          const SizedBox(height: 8),
          Text(
            'Tip: tap the map to drop a pin instead.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
