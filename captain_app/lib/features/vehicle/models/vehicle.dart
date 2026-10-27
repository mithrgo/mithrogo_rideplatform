class Vehicle {
  const Vehicle({
    required this.id,
    required this.type,
    required this.registrationNumber,
    required this.make,
    required this.model,
    required this.color,
    required this.isVerified,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: (json['id'] as num).toInt(),
      type: json['vehicle_type'] as String,
      registrationNumber: (json['registration_number'] as String?) ?? '',
      make: (json['make'] as String?) ?? '',
      model: (json['model'] as String?) ?? '',
      color: (json['color'] as String?) ?? '',
      isVerified: json['is_verified'] == true,
    );
  }

  final int id;
  final String type;
  final String registrationNumber;
  final String make;
  final String model;
  final String color;
  final bool isVerified;

  String get typeLabel => vehicleTypeLabel(type);
}

const vehicleTypes = <String, String>{'BIKE': 'Bike', 'AUTO': 'Auto'};

String vehicleTypeLabel(String? type) => vehicleTypes[type] ?? (type ?? '');
