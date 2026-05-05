class PatientModel {
  final String id;
  final String name;
  final int age;
  final String gender;
  final String phone;
  final String location;
  final String? hairLossHistory;
  final String? diseases;
  final String? medications;
  final String? dietType;
  final String? smokingStatus;
  final String? stressLevel;
  final String? sleepQuality;
  final String? exerciseFrequency;

  const PatientModel({
    required this.id,
    required this.name,
    required this.age,
    required this.gender,
    required this.phone,
    required this.location,
    this.hairLossHistory,
    this.diseases,
    this.medications,
    this.dietType,
    this.smokingStatus,
    this.stressLevel,
    this.sleepQuality,
    this.exerciseFrequency,
  });

  factory PatientModel.fromJson(Map<String, dynamic> json) => PatientModel(
        id: (json['id'] ?? json['userId'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        age: (json['age'] as num?)?.toInt() ?? 0,
        gender: (json['gender'] ?? '').toString(),
        phone: (json['phone'] ?? json['mobile'] ?? '').toString(),
        location: (json['location'] ?? json['address'] ?? '').toString(),
        hairLossHistory: json['hairLossHistory']?.toString(),
        diseases: json['diseases']?.toString(),
        medications: json['medications']?.toString(),
        dietType: json['dietType']?.toString(),
        smokingStatus: json['smokingStatus']?.toString(),
        stressLevel: json['stressLevel']?.toString(),
        sleepQuality: json['sleepQuality']?.toString(),
        exerciseFrequency: json['exerciseFrequency']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'age': age,
        'gender': gender,
        'phone': phone,
        'location': location,
        'hairLossHistory': hairLossHistory,
        'diseases': diseases,
        'medications': medications,
        'dietType': dietType,
        'smokingStatus': smokingStatus,
        'stressLevel': stressLevel,
        'sleepQuality': sleepQuality,
        'exerciseFrequency': exerciseFrequency,
      };
}
