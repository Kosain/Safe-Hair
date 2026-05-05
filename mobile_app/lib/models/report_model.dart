class ReportModel {
  final String id;
  final String userId;
  final String type; // 'scalp_analysis', 'consultation', 'graft_estimate'
  final String title;
  final String? doctorName;
  final DateTime date;
  final Map<String, dynamic> summary;
  final List<String> recommendations;
  final String? documentUrl;

  ReportModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    this.doctorName,
    required this.date,
    this.summary = const {},
    this.recommendations = const [],
    this.documentUrl,
  });

  factory ReportModel.fromMap(Map<String, dynamic> map) {
    return ReportModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? map['user_id'] ?? '',
      type: map['type'] ?? 'scalp_analysis',
      title: map['title'] ?? 'Report',
      doctorName: map['doctorName'] ?? map['doctor_name'],
      date: map['date'] != null
          ? DateTime.tryParse(map['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      summary: Map<String, dynamic>.from(map['summary'] ?? {}),
      recommendations: List<String>.from(map['recommendations'] ?? []),
      documentUrl: map['documentUrl'] ?? map['document_url'],
    );
  }
}
