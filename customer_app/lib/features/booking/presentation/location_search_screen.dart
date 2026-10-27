import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../app/config/env.dart';
import '../../../app/providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/location/location_service.dart';
import '../../../core/location/place.dart';
import '../application/booking_controller.dart';
import '../application/place_search_controller.dart';

/// Pickup and drop search, like the "Where to?" screen in Uber and Rapido.
///
/// Nearby results need the rider's GPS position. Named places ("railway station Hyderabad")
/// search all of India and do not need it.
class LocationSearchScreen extends ConsumerStatefulWidget {
  const LocationSearchScreen({super.key});

  @override
  ConsumerState<LocationSearchScreen> createState() => _LocationSearchScreenState();
}

class _LocationSearchScreenState extends ConsumerState<LocationSearchScreen> {
  static const _currentLocationLabel = 'Current location';

  late final TextEditingController _pickupController;
  late final TextEditingController _dropController;
  bool _editingDrop = true;

  @override
  void initState() {
    super.initState();
    final booking = ref.read(bookingControllerProvider);
    _pickupController = TextEditingController(text: booking.pickup?.name ?? _currentLocationLabel);
    _dropController = TextEditingController(text: booking.drop?.name ?? '');
    // Ask for a fresh fix when the screen opens, so a search never starts from an old position.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(currentLocationProvider);
    });
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropController.dispose();
    super.dispose();
  }

  PlaceSearchController get _search => ref.read(placeSearchControllerProvider.notifier);

  /// Makes one field the active one and searches its text.
  void _activate({required bool drop}) {
    if (!drop && _pickupController.text == _currentLocationLabel) {
      // The label is not a place name, so start the pickup search empty.
      _pickupController.clear();
    }
    setState(() => _editingDrop = drop);
    _search.onQueryChanged(drop ? _dropController.text : _pickupController.text);
  }

  void _selectPlace(Place place) {
    final notifier = ref.read(bookingControllerProvider.notifier);
    if (_editingDrop) {
      notifier.setDrop(place);
      context.pop();
      return;
    }
    notifier.setPickup(place);
    _pickupController.text = place.name;
    _activate(drop: true);
  }

  void _useCurrentLocation() {
    ref.read(bookingControllerProvider.notifier).useCurrentLocationForPickup();
    _pickupController.text = _currentLocationLabel;
    _activate(drop: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Watching keeps the GPS fix alive. A new fix re-runs a nearby search from the new position.
    ref.listen(currentLocationProvider, (previous, next) {
      final before = previous?.valueOrNull;
      final after = next.valueOrNull;
      if (after != null && after != before) _search.onLocationChanged();
    });
    final search = ref.watch(placeSearchControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Plan your ride')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 4))],
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
                        Container(width: 2, height: 28, color: AppColors.divider),
                        Container(width: 10, height: 10, color: AppColors.ink),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          _FieldRow(
                            controller: _pickupController,
                            hint: 'Pickup',
                            active: !_editingDrop,
                            onTap: () => _activate(drop: false),
                            onChanged: _search.onQueryChanged,
                          ),
                          const Divider(height: 1),
                          _FieldRow(
                            controller: _dropController,
                            hint: 'Where to?',
                            active: _editingDrop,
                            onTap: () => _activate(drop: true),
                            onChanged: _search.onQueryChanged,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (!_editingDrop)
                    ListTile(
                      leading: const Icon(Icons.my_location, color: AppColors.ink),
                      title: const Text('Use current location'),
                      subtitle: const Text('Your device location'),
                      onTap: _useCurrentLocation,
                    ),
                  ..._resultRows(search, theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _resultRows(PlaceSearchState search, ThemeData theme) {
    final radiusKm = Env.localSearchRadiusMeters ~/ 1000;
    final expandedKm = Env.expandedSearchRadiusMeters ~/ 1000;

    switch (search.status) {
      case PlaceSearchStatus.idle:
        return [
          _Message(
            'Search for a place. Nearby results use your location. '
            'For another city, add its name, such as "railway station Hyderabad".',
            theme: theme,
          ),
        ];
      case PlaceSearchStatus.tooShort:
        return [_Message('Type at least ${PlaceSearchController.minQueryLength} letters.', theme: theme)];
      case PlaceSearchStatus.loading:
        return const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ];
      case PlaceSearchStatus.needsLocation:
        return [
          _LocationRequired(
            message: search.error ?? 'Nearby search needs your location.',
            failure: search.locationFailure,
            theme: theme,
          ),
        ];
      case PlaceSearchStatus.error:
        return [
          ListTile(
            leading: const Icon(Icons.error_outline, color: AppColors.danger),
            title: Text(search.error ?? 'Search failed.', style: theme.textTheme.bodyMedium),
            trailing: TextButton(
              onPressed: () => ref.read(placeSearchControllerProvider.notifier).retry(),
              child: const Text('Retry'),
            ),
          ),
        ];
      case PlaceSearchStatus.loaded:
        return [
          if (search.notice != null)
            _Message(search.notice!, theme: theme),
          if (!search.hasResults && search.explicit)
            _Message('No places found for "${search.query}" in India.', theme: theme),
          if (!search.hasResults && !search.explicit)
            _Message(
              'Nothing for "${search.query}" within $radiusKm km of you.',
              theme: theme,
            ),
          if (search.explicit && search.beyond.isNotEmpty)
            _SectionHeader('Matches across India', theme: theme),
          if (!search.explicit && search.nearby.isNotEmpty)
            _SectionHeader('Within $radiusKm km of you', theme: theme),
          for (final place in search.nearby) _placeTile(place, theme),
          if (search.canExpand) ...[
            _Message('No nearby results. You can search a wider area.', theme: theme),
            ListTile(
              leading: const Icon(Icons.travel_explore, color: AppColors.ink),
              title: const Text('Expand search area'),
              subtitle: Text('Looks up to $expandedKm km away. Results may be far from you.'),
              onTap: () => ref.read(placeSearchControllerProvider.notifier).expandSearch(),
            ),
          ],
          if (search.expanded && search.beyond.isNotEmpty)
            _SectionHeader('Further than $radiusKm km', theme: theme),
          for (final place in search.beyond) _placeTile(place, theme),
        ];
    }
  }

  Widget _placeTile(Place place, ThemeData theme) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.place_outlined, color: AppColors.ink, size: 20),
      ),
      title: Text(place.name, style: theme.textTheme.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        place.subtitle.isEmpty ? place.address : place.subtitle,
        style: theme.textTheme.bodySmall,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _selectPlace(place),
    );
  }
}

/// Shown instead of nearby results when the GPS position is not available.
/// It offers a retry, a settings shortcut where that helps, and the manual route.
class _LocationRequired extends ConsumerWidget {
  const _LocationRequired({required this.message, required this.failure, required this.theme});

  final String message;
  final LocationFailure? failure;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsSettings = failure == LocationFailure.servicesDisabled ||
        failure == LocationFailure.permissionDeniedForever;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_off_outlined, color: AppColors.danger, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Nearby search needs your location. You can still type a place with a city name, '
            'such as "railway station Hyderabad", or choose a pickup point manually.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => ref.read(placeSearchControllerProvider.notifier).retry(),
                child: const Text('Retry location'),
              ),
              if (needsSettings)
                TextButton(
                  onPressed: () => failure == LocationFailure.servicesDisabled
                      ? Geolocator.openLocationSettings()
                      : Geolocator.openAppSettings(),
                  child: const Text('Open settings'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text, {required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: AppColors.textSecondary)),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.controller,
    required this.hint,
    required this.active,
    required this.onTap,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onTap: onTap,
      onChanged: onChanged,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
      decoration: InputDecoration(
        hintText: hint,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}
