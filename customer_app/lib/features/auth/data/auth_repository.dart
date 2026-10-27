import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/app_user.dart';

class AuthResult {
  const AuthResult({required this.user, required this.access, required this.refresh});

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
      access: json['access'] as String,
      refresh: json['refresh'] as String,
    );
  }

  final AppUser user;
  final String access;
  final String refresh;
}

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<void> sendOtp(String phone) async {
    await _api.send((dio) => dio.post<Map<String, dynamic>>(
          ApiEndpoints.sendOtp,
          data: {'phone': phone},
        ));
  }

  Future<AuthResult> verifyOtp({required String phone, required String code}) async {
    final response = await _api.send((dio) => dio.post<Map<String, dynamic>>(
          ApiEndpoints.verifyOtp,
          data: {'phone': phone, 'code': code, 'role': 'CUSTOMER'},
        ));
    return AuthResult.fromJson(response.data!);
  }

  Future<AppUser> me() async {
    final response = await _api.send((dio) => dio.get<Map<String, dynamic>>(ApiEndpoints.me));
    return AppUser.fromJson(response.data!);
  }

  /// Reasons the account can't be deleted right now (an active ride, unpaid fees); empty when it can.
  Future<List<String>> deletionBlockers() async {
    final response = await _api.send((dio) => dio.get<Map<String, dynamic>>(ApiEndpoints.deleteAccount));
    return [for (final reason in (response.data!['reasons'] as List? ?? const [])) reason.toString()];
  }

  Future<void> deleteAccount() async {
    await _api.send((dio) => dio.post<void>(
          ApiEndpoints.deleteAccount,
          data: {'confirm': true},
        ));
  }

  Future<void> logout(String refresh) async {
    await _api.send((dio) => dio.post<void>(
          ApiEndpoints.logout,
          data: {'refresh': refresh},
        ));
  }
}
