enum KycStatus { pending, underReview, approved, rejected, suspended }

KycStatus _kycFrom(String? value) => switch (value) {
      'UNDER_REVIEW' => KycStatus.underReview,
      'APPROVED' => KycStatus.approved,
      'REJECTED' => KycStatus.rejected,
      'SUSPENDED' => KycStatus.suspended,
      _ => KycStatus.pending,
    };

class CaptainProfile {
  const CaptainProfile({
    required this.phone,
    required this.kycStatus,
    required this.rejectionReason,
    required this.licenseNumber,
    required this.licenseExpiry,
    required this.dateOfBirth,
    required this.address,
    required this.rating,
    required this.totalRides,
  });

  factory CaptainProfile.fromJson(Map<String, dynamic> json) {
    return CaptainProfile(
      phone: (json['phone'] as String?) ?? '',
      kycStatus: _kycFrom(json['kyc_status'] as String?),
      rejectionReason: (json['kyc_rejection_reason'] as String?) ?? '',
      licenseNumber: (json['license_number'] as String?) ?? '',
      licenseExpiry: json['license_expiry'] as String?,
      dateOfBirth: json['date_of_birth'] as String?,
      address: (json['address'] as String?) ?? '',
      rating: json['rating']?.toString() ?? '0',
      totalRides: (json['total_rides'] as num?)?.toInt() ?? 0,
    );
  }

  final String phone;
  final KycStatus kycStatus;
  final String rejectionReason;
  final String licenseNumber;
  final String? licenseExpiry;
  final String? dateOfBirth;
  final String address;
  final String rating;
  final int totalRides;
}

class KycDocument {
  const KycDocument({required this.id, required this.docType});

  factory KycDocument.fromJson(Map<String, dynamic> json) =>
      KycDocument(id: (json['id'] as num).toInt(), docType: json['doc_type'] as String);

  final int id;
  final String docType;
}

/// Document types the captain uploads from the app, with the label shown for each.
const kycDocTypes = <String, String>{
  'DRIVING_LICENSE': 'Driving licence',
  'IDENTITY': 'ID proof (Aadhaar / PAN)',
  'VEHICLE_REGISTRATION': 'Vehicle registration (RC)',
  'PHOTO': 'Your photo',
};
