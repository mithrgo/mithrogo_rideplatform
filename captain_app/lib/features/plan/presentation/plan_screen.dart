import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/common.dart';
import '../../home/application/home_controller.dart';
import '../../vehicle/models/vehicle.dart';
import '../data/plan_repository.dart';

class _PlanData {
  const _PlanData(this.plans, this.summary, this.balance);

  final List<Plan> plans;
  final PlanSummary summary;
  final String balance;
}

final _planDataProvider = FutureProvider.autoDispose<_PlanData>((ref) async {
  final repo = ref.watch(planRepositoryProvider);
  final results = await Future.wait([repo.plans(), repo.summary(), repo.walletBalance()]);
  return _PlanData(results[0] as List<Plan>, results[1] as PlanSummary, results[2] as String);
});

/// Choose how to work: a daily plan paid from the wallet, or the free ride-share plan.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  String? _busyCode;

  Future<void> _choose(Plan plan) async {
    setState(() => _busyCode = plan.code);
    try {
      final repo = ref.read(planRepositoryProvider);
      if (plan.isRideShare) {
        await repo.switchToRideShare(plan.code);
      } else {
        await repo.buyDailyFromWallet(plan.code);
      }
      ref.invalidate(_planDataProvider);
      await ref.read(homeControllerProvider.notifier).refresh();
      if (mounted) showMessage(context, '${plan.name} is active.');
    } catch (error) {
      if (mounted) showMessage(context, userMessage(error));
    } finally {
      if (mounted) setState(() => _busyCode = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_planDataProvider);
    final todayType = ref.watch(homeControllerProvider).status?.todayVehicleType;

    return Scaffold(
      appBar: AppBar(title: const Text('Choose a plan')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(message: userMessage(error), onRetry: () => ref.invalidate(_planDataProvider)),
        data: (data) {
          // Show only plans for today's vehicle once one is chosen.
          final plans = data.plans.where((p) => p.vehicleType == null || todayType == null || p.vehicleType == todayType);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              InfoCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Wallet balance'),
                        Text(formatInr(data.balance), style: Theme.of(context).textTheme.headlineMedium),
                      ],
                    ),
                    if (data.summary.planName != null) StatusChip(label: data.summary.planName!, color: Colors.green),
                  ],
                ),
              ),
              if (data.summary.message.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(data.summary.message),
              ],
              const SizedBox(height: 20),
              for (final plan in plans)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InfoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(plan.name, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text([
                          if (plan.vehicleType != null) vehicleTypeLabel(plan.vehicleType),
                          if (plan.isRideShare) 'No upfront fee, platform takes a share of rides' else '${formatInr(plan.amount)} for ${plan.durationHours ?? 12} hours',
                        ].join(' · ')),
                        const SizedBox(height: 12),
                        PrimaryButton(
                          label: plan.isRideShare ? 'Switch to this plan' : 'Pay from wallet',
                          busy: _busyCode == plan.code,
                          onPressed: _busyCode == null ? () => _choose(plan) : null,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Used by the earnings tab to settle dues from the wallet.
Future<String?> payDuesFromWallet(WidgetRef ref) async {
  try {
    await ref.read(planRepositoryProvider).payDuesFromWallet();
    return null;
  } on ApiException catch (error) {
    return error.message;
  }
}
