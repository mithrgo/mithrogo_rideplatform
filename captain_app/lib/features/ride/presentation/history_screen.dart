import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/common.dart';
import '../models/ride.dart';

final rideHistoryProvider = FutureProvider.autoDispose<List<Ride>>((ref) {
  return ref.watch(rideRepositoryProvider).rides();
});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rides = ref.watch(rideHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ride history')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(rideHistoryProvider.future),
        child: rides.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorView(message: userMessage(error), onRetry: () => ref.invalidate(rideHistoryProvider)),
          data: (rides) => rides.isEmpty
              ? ListView(children: const [SizedBox(height: 120), Center(child: Text('No rides yet.'))])
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: rides.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final ride = rides[index];
                    final done = ride.status == 'COMPLETED';
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => context.push('/ride/${ride.id}'),
                      child: InfoCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(formatInr(ride.fare), style: Theme.of(context).textTheme.titleMedium),
                                const Spacer(),
                                StatusChip(
                                  label: ride.statusLabel,
                                  color: done ? AppColors.success : (ride.status == 'CANCELLED' ? AppColors.danger : AppColors.info),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(ride.pickupAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text('to ${ride.dropAddress}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
