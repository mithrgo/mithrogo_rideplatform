import 'package:dio/dio.dart';

import '../../app/config/env.dart';
import '../constants/app_constants.dart';
import '../storage/token_storage.dart';
import 'api_endpoints.dart';
import 'api_exception.dart';

/// Dio wrapper that attaches the access token and refreshes it once on 401.
class ApiClient {
  ApiClient({
    required this._tokenStorage,
    required this._onSessionExpired,
  })  : _dio = _buildDio() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError: _onError,
    ));
  }

  static const _retriedKey = 'retried';

  final TokenStorage _tokenStorage;
  final void Function() _onSessionExpired;
  final Dio _dio;

  // Shared by concurrent 401s, so only one refresh call is sent.
  Future<String?>? _refreshing;

  static Dio _buildDio() => Dio(BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: AppConstants.requestTimeout,
        receiveTimeout: AppConstants.requestTimeout,
        headers: {'Accept': 'application/json'},
      ));

  /// Runs a request and converts Dio errors into [ApiException].
  Future<Response<T>> send<T>(Future<Response<T>> Function(Dio dio) request) async {
    try {
      return await request(_dio);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> _onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _tokenStorage.readAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(DioException error, ErrorInterceptorHandler handler) async {
    final options = error.requestOptions;
    final alreadyRetried = options.extra[_retriedKey] == true;
    final isRefreshCall = options.path == ApiEndpoints.refresh;

    if (error.response?.statusCode != 401 || alreadyRetried || isRefreshCall) {
      return handler.next(error);
    }

    final newAccess = await (_refreshing ??= _refreshAccessToken().whenComplete(() {
      _refreshing = null;
    }));

    if (newAccess == null) {
      _onSessionExpired();
      return handler.next(error);
    }

    options.extra[_retriedKey] = true;
    options.headers['Authorization'] = 'Bearer $newAccess';
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<String?> _refreshAccessToken() async {
    final refresh = await _tokenStorage.readRefreshToken();
    if (refresh == null) return null;

    try {
      // A fresh Dio without interceptors, so a failed refresh can't recurse.
      final response = await _buildDio().post<Map<String, dynamic>>(
        ApiEndpoints.refresh,
        data: {'refresh': refresh},
      );
      final data = response.data ?? const <String, dynamic>{};
      final access = data['access'] as String?;
      final newRefresh = data['refresh'] as String?;
      if (access == null || newRefresh == null) return null;

      await _tokenStorage.save(access: access, refresh: newRefresh);
      return access;
    } on DioException {
      return null;
    }
  }
}
