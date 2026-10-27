import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/common.dart';
import '../../auth/application/session_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../models/vehicle.dart';

/// Add vehicles and see whether an admin has verified them. Used during onboarding (no verified
/// vehicle yet) and from the profile tab.
class VehicleScreen extends ConsumerStatefulWidget {
  const VehicleScreen({super.key, this.onboarding = false});

  /// True when this is a required onboarding step, which has no back button and offers sign out.
  final bool onboarding;

  @override
  ConsumerState<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends ConsumerState<VehicleScreen> {
  final _registration = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _color = TextEditingController();
  String _type = 'BIKE';
  List<Vehicle> _vehicles = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Verification happens in the admin console, so keep checking while this screen is open.
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _registration.dispose();
    _make.dispose();
    _model.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final vehicles = await ref.read(vehicleRepositoryProvider).vehicles();
      if (!mounted) return;
      final becameVerified = vehicles.any((v) => v.isVerified) && !_vehicles.any((v) => v.isVerified);
      setState(() {
        _vehicles = vehicles;
        _loading = false;
      });
      if (becameVerified) await ref.read(onboardingProvider.notifier).refresh();
    } on ApiException catch (error) {
      if (mounted && !silent) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _add() async {
    if (_registration.text.trim().isEmpty) {
      setState(() => _error = 'Enter the registration number.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(vehicleRepositoryProvider).add(
            type: _type,
            registrationNumber: _registration.text.trim().toUpperCase(),
            make: _make.text.trim(),
            model: _model.text.trim(),
            color: _color.text.trim(),
          );
      _registration.clear();
      _make.clear();
      _model.clear();
      _color.clear();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = userMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final addedTypes = {for (final v in _vehicles) v.type};
    final freeTypes = vehicleTypes.keys.where((t) => !addedTypes.contains(t)).toList();
    if (freeTypes.isNotEmpty && !freeTypes.contains(_type)) _type = freeTypes.first;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your vehicles'),
        automaticallyImplyLeading: !widget.onboarding,
        actions: [
          if (widget.onboarding)
            TextButton(
              onPressed: () => ref.read(sessionControllerProvider.notifier).signOut(),
              child: const Text('Sign out'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (widget.onboarding && _vehicles.isNotEmpty && !_vehicles.any((v) => v.isVerified))
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: InfoCard(child: Text('Your vehicle is waiting for admin verification. This updates by itself.')),
                  ),
                for (final v in _vehicles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InfoCard(
                      child: Row(
                        children: [
                          Icon(v.type == 'AUTO' ? Icons.electric_rickshaw : Icons.two_wheeler, size: 32),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v.registrationNumber, style: Theme.of(context).textTheme.titleMedium),
                                Text([v.typeLabel, v.make, v.model, v.color].where((s) => s.isNotEmpty).join(' · ')),
                              ],
                            ),
                          ),
                          StatusChip(
                            label: v.isVerified ? 'Verified' : 'Pending',
                            color: v.isVerified ? AppColors.success : AppColors.brandDark,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (freeTypes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Add a vehicle', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: [for (final t in freeTypes) ButtonSegment(value: t, label: Text(vehicleTypes[t]!))],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() => _type = s.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _registration,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Registration number'),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _make, decoration: const InputDecoration(labelText: 'Make (optional)')),
                  const SizedBox(height: 12),
                  TextField(controller: _model, decoration: const InputDecoration(labelText: 'Model (optional)')),
                  const SizedBox(height: 12),
                  TextField(controller: _color, decoration: const InputDecoration(labelText: 'Colour (optional)')),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 20),
                  PrimaryButton(label: 'Add vehicle', busy: _saving, onPressed: _add),
                ],
              ],
            ),
    );
  }
}
