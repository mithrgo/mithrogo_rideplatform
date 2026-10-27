import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

class Earnings {
  const Earnings({
    required this.completedRides,
    required this.fareTotal,
    required this.platformShare,
    required this.netEarnings,
    required this.todayRides,
    required this.todayNet,
    required this.pendingDues,
  });

  factory Earnings.fromJson(Map<String, dynamic> json) {
    final today = (json['today'] as Map?) ?? const {};
    return Earnings(
      completedRides: (json['completed_rides'] as num?)?.toInt() ?? 0,
      fareTotal: json['fare_total']?.toString() ?? '0',
      platformShare: json['platform_share']?.toString() ?? '0',
      netEarnings: json['net_earnings']?.toString() ?? '0',
      todayRides: (today['completed_rides'] as num?)?.toInt() ?? 0,
      todayNet: today['net_earnings']?.toString() ?? '0',
      pendingDues: json['pending_dues']?.toString() ?? '0',
    );
  }

  final int completedRides;
  final String fareTotal;
  final String platformShare;
  final String netEarnings;
  final int todayRides;
  final String todayNet;
  final String pendingDues;
}

class EarningsRepository {
  EarningsRepository(this._api);

  final ApiClient _api;

  Future<Earnings> earnings() async {
    final response = await _api.send((dio) => dio.get<Map<String, dynamic>>(ApiEndpoints.earnings));
    return Earnings.fromJson(response.data!);
  }
}
