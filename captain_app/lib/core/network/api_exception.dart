import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../location/location_service.dart';

/// A failed API call, with the backend's message converted for display.
///
/// The backend returns `{"detail": "...", "code": "..."}` for rule errors and
/// DRF's `{"field": ["..."]}` for validation errors.
class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.code,
    this.statusCode,
    this.fieldErrors = const {},
  });

  final String message;
  final String? code;

  /// Null when the request never got a response (no connection, timeout).
  final int? statusCode;

  /// First error message per field, for showing next to form inputs.
  final Map<String, String> fieldErrors;

  bool get isUnauthorized => statusCode == 401;

  bool get isNetworkError => statusCode == null;

  factory ApiException.fromDio(DioException error) {
    final response = error.response;
    if (response == null) {
      debugPrint('API unreachable: ${error.type} ${error.requestOptions.uri} ${error.error}');
      return const ApiException(
        message: 'Cannot reach the server. Check your connection and try again.',
      );
    }

    final status = response.statusCode;
    final data = response.data;

    if (data is Map) {
      final detail = data['detail'];
      if (detail is String) {
        return ApiException(message: detail, code: data['code']?.toString(), statusCode: status);
      }

      final fields = <String, String>{};
      data.forEach((key, value) {
        if (value is List && value.isNotEmpty) {
          fields[key.toString()] = value.first.toString();
        } else if (value is String) {
          fields[key.toString()] = value;
        }
      });
      if (fields.isNotEmpty) {
        return ApiException(
          message: fields.values.first,
          code: 'validation_error',
          statusCode: status,
          fieldErrors: fields,
        );
      }
    }

    return ApiException(message: 'Something went wrong. Please try again.', statusCode: status);
  }

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

/// Turns any error from a repository call into a message that is safe to show.
String userMessage(Object error) {
  if (error is ApiException) return error.message;
  if (error is LocationException) return error.message;
  return 'Something went wrong. Please try again.';
}
