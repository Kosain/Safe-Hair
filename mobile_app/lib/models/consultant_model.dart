class ConsultantModel {
  final String id;
  final String name;
  final String clinicName;
  final String location;
  final String specialization;
  final double rating;
  final int consultationFee;

  const ConsultantModel({
    required this.id,
    required this.name,
    required this.clinicName,
    required this.location,
    required this.specialization,
    required this.rating,
    required this.consultationFee,
  });

  factory ConsultantModel.fromJson(Map<String, dynamic> json) {
    return ConsultantModel(
      id: (json['id'] ?? json['userId'] ?? '').toString(),
      name: (json['name'] ?? json['fullName'] ?? '').toString(),
      clinicName: (json['clinicName'] ?? '').toString(),
      location: (json['location'] ?? json['clinicLocation'] ?? '').toString(),
      specialization: (json['specialization'] ?? '').toString(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      consultationFee: (json['consultation_fee'] as num?)?.toInt() ?? 0,
    );
  }
}
