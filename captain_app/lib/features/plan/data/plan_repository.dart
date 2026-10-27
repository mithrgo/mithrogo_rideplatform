import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

class Plan {
  const Plan({
    required this.code,
    required this.name,
    required this.planType,
    required this.amount,
    required this.vehicleType,
    required this.durationHours,
  });

  factory Plan.fromJson(Map<String, dynamic> json) {
    return Plan(
      code: json['code'] as String,
      name: (json['name'] as String?) ?? json['code'] as String,
      planType: (json['plan_type'] as String?) ?? '',
      amount: json['amount']?.toString() ?? '0',
      vehicleType: json['vehicle_type'] as String?,
      durationHours: (json['duration_hours'] as num?)?.toInt(),
    );
  }

  final String code;
  final String name;
  final String planType;
  final String amount;
  final String? vehicleType;
  final int? durationHours;

  bool get isRideShare => code.startsWith('RIDE_SHARE');
}

class PlanSummary {
  const PlanSummary({required this.planName, required this.expiresAt, required this.pendingDues, required this.message});

  factory PlanSummary.fromJson(Map<String, dynamic> json) {
    final sub = json['subscription'] as Map<String, dynamic>?;
    final plan = sub?['plan'] as Map<String, dynamic>?;
    final active = sub?['status'] == 'ACTIVE';
    return PlanSummary(
      planName: active ? (plan?['name'] as String?) : null,
      expiresAt: active ? DateTime.tryParse((sub?['expires_at'] as String?) ?? '') : null,
      pendingDues: json['pending_dues']?.toString() ?? '0',
      message: (json['message'] as String?) ?? '',
    );
  }

  /// Null when no plan is active.
  final String? planName;
  final DateTime? expiresAt;
  final String pendingDues;
  final String message;
}

class PlanRepository {
  PlanRepository(this._api);

  final ApiClient _api;

  List _list(dynamic data) => data is Map ? (data['results'] as List? ?? const []) : (data as List? ?? const []);

  Future<List<Plan>> plans() async {
    final response = await _api.send((dio) => dio.get<dynamic>(ApiEndpoints.plans));
    return [for (final item in _list(response.data)) Plan.fromJson(item as Map<String, dynamic>)];
  }

  Future<PlanSummary> summary() async {
    final response = await _api.send((dio) => dio.get<Map<String, dynamic>>(ApiEndpoints.subscription));
    return PlanSummary.fromJson(response.data!);
  }

  Future<String> walletBalance() async {
    final response = await _api.send((dio) => dio.get<Map<String, dynamic>>(ApiEndpoints.wallet));
    return response.data!['balance']?.toString() ?? '0';
  }

  /// Buys a daily plan from the wallet balance. It activates at once.
  Future<void> buyDailyFromWallet(String planCode) async {
    await _api.send((dio) => dio.post<dynamic>(ApiEndpoints.walletPayPlan, data: {'plan_code': planCode}));
  }

  Future<void> switchToRideShare(String planCode) async {
    await _api.send((dio) => dio.post<dynamic>(ApiEndpoints.switchPlan, data: {'plan_code': planCode}));
  }

  Future<void> payDuesFromWallet() async {
    await _api.send((dio) => dio.post<dynamic>(ApiEndpoints.walletPayDues));
  }
}
