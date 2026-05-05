class AppointmentModel {
  final String id;
  final String userId;
  final String doctorId;
  final String doctorName;
  final String date;
  final String timeSlot;
  final int reminderMinutes;
  final String status;
  final String? consultationNotes;
  final DateTime createdAt;

  AppointmentModel({
    required this.id,
    required this.userId,
    required this.doctorId,
    required this.doctorName,
    required this.date,
    required this.timeSlot,
    this.reminderMinutes = 30,
    this.status = 'confirmed',
    this.consultationNotes,
    required this.createdAt,
  });

  factory AppointmentModel.fromMap(Map<String, dynamic> map) {
    return AppointmentModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? map['user_id'] ?? '',
      doctorId: map['doctorId'] ?? map['doctor_id'] ?? '',
      doctorName: map['doctorName'] ?? map['doctor_name'] ?? '',
      date: map['date'] ?? '',
      timeSlot: map['timeSlot'] ?? map['time_slot'] ?? '',
      reminderMinutes: map['reminderMinutes'] ?? map['reminder_minutes'] ?? 30,
      status: map['status'] ?? 'confirmed',
      consultationNotes: map['consultationNotes'] ?? map['consultation_notes'],
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'doctorId': doctorId,
        'doctorName': doctorName,
        'date': date,
        'timeSlot': timeSlot,
        'reminderMinutes': reminderMinutes,
        'status': status,
        'consultationNotes': consultationNotes,
        'createdAt': createdAt.toIso8601String(),
      };
}
