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
    await _api.send((dio) => dio.post<Map<String, dynamic>>(ApiEndpoints.sendOtp, data: {'phone': phone}));
  }

  Future<AuthResult> verifyOtp({required String phone, required String code}) async {
    final response = await _api.send((dio) => dio.post<Map<String, dynamic>>(
          ApiEndpoints.verifyOtp,
          data: {'phone': phone, 'code': code, 'role': 'CAPTAIN'},
        ));
    return AuthResult.fromJson(response.data!);
  }

  Future<AppUser> me() async {
    final response = await _api.send((dio) => dio.get<Map<String, dynamic>>(ApiEndpoints.me));
    return AppUser.fromJson(response.data!);
  }

  Future<void> logout(String refresh) async {
    await _api.send((dio) => dio.post<void>(ApiEndpoints.logout, data: {'refresh': refresh}));
  }
}
