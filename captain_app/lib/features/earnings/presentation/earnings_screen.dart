import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/common.dart';
import '../../home/application/home_controller.dart';
import '../../plan/presentation/plan_screen.dart';
import '../data/earnings_repository.dart';

final earningsProvider = FutureProvider.autoDispose<Earnings>((ref) {
  return ref.watch(earningsRepositoryProvider).earnings();
});

class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earnings = ref.watch(earningsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(earningsProvider.future),
        child: earnings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorView(message: userMessage(error), onRetry: () => ref.invalidate(earningsProvider)),
          data: (e) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              InfoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Today'),
                    Text(formatInr(e.todayNet), style: Theme.of(context).textTheme.displaySmall),
                    Text('${e.todayRides} rides'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InfoCard(
                child: Column(
                  children: [
                    _Line('Rides completed', '${e.completedRides}'),
                    _Line('Total fares', formatInr(e.fareTotal)),
                    _Line('Platform share', formatInr(e.platformShare)),
                    const Divider(),
                    _Line('Net earnings', formatInr(e.netEarnings), bold: true),
                  ],
                ),
              ),
              if (double.tryParse(e.pendingDues) != null && double.parse(e.pendingDues) > 0) ...[
                const SizedBox(height: 12),
                InfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pending dues: ${formatInr(e.pendingDues)}', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      PrimaryButton(
                        label: 'Pay from wallet',
                        onPressed: () async {
                          final error = await payDuesFromWallet(ref);
                          if (!context.mounted) return;
                          showMessage(context, error ?? 'Dues paid.');
                          ref.invalidate(earningsProvider);
                          ref.read(homeControllerProvider.notifier).refresh();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontSize: 15);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
