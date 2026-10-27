import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/network/api_exception.dart';

/// Shown on the home screen when the device position is unavailable.
/// Offers a retry, and a settings shortcut when the phone must change something.
class LocationBanner extends ConsumerWidget {
  const LocationBanner({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failure = error is LocationException
        ? (error as LocationException).failure
        : LocationFailure.unavailable;
    final needsSettings = error is LocationException && (error as LocationException).needsSettings;

    return Material(
      color: AppColors.card,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        child: Row(
          children: [
            const Icon(Icons.location_off_outlined, color: AppColors.danger, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                userMessage(error),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(currentLocationProvider),
              child: const Text('Retry'),
            ),
            if (needsSettings)
              TextButton(
                onPressed: () => failure == LocationFailure.servicesDisabled
                    ? Geolocator.openLocationSettings()
                    : Geolocator.openAppSettings(),
                child: const Text('Settings'),
              ),
          ],
        ),
      ),
    );
  }
}
