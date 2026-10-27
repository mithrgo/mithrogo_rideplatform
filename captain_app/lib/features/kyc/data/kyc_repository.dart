import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/captain_profile.dart';

class KycRepository {
  KycRepository(this._api);

  final ApiClient _api;

  Future<CaptainProfile> profile() async {
    final response = await _api.send((dio) => dio.get<Map<String, dynamic>>(ApiEndpoints.profile));
    return CaptainProfile.fromJson(response.data!);
  }

  Future<List<KycDocument>> documents() async {
    final response = await _api.send((dio) => dio.get<dynamic>(ApiEndpoints.kycDocuments));
    final data = response.data;
    final list = data is Map ? (data['results'] as List? ?? const []) : (data as List? ?? const []);
    return [for (final item in list) KycDocument.fromJson(item as Map<String, dynamic>)];
  }

  Future<void> uploadDocument({required String docType, required String path, required String filename}) async {
    final form = FormData.fromMap({
      'doc_type': docType,
      'file': await MultipartFile.fromFile(path, filename: filename),
    });
    await _api.send((dio) => dio.post<Map<String, dynamic>>(ApiEndpoints.kycDocuments, data: form));
  }

  /// Sends the details for admin review. The backend sets the status to UNDER_REVIEW.
  Future<CaptainProfile> submit({
    required String licenseNumber,
    required String licenseExpiry,
    required String dateOfBirth,
    required String address,
  }) async {
    final response = await _api.send((dio) => dio.post<Map<String, dynamic>>(ApiEndpoints.kyc, data: {
          'license_number': licenseNumber,
          'license_expiry': licenseExpiry,
          'date_of_birth': dateOfBirth,
          'address': address,
        }));
    return CaptainProfile.fromJson(response.data!);
  }
}
