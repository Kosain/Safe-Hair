class ScalpAnalysisResultModel {
  final String severityGrade;
  final int graftsRequired;
  final double confidenceScore;
  final List<String> treatmentSuggestions;
  final String? recommendationSummary;

  const ScalpAnalysisResultModel({
    required this.severityGrade,
    required this.graftsRequired,
    required this.confidenceScore,
    required this.treatmentSuggestions,
    this.recommendationSummary,
  });

  factory ScalpAnalysisResultModel.fromJson(Map<String, dynamic> json) {
    final graftsRaw = json['graftsRequired'] ?? json['grafts_required'];
    final confidenceRaw = json['confidenceScore'] ?? json['confidence_score'];
    return ScalpAnalysisResultModel(
      severityGrade: (json['severityGrade'] ?? json['severity_grade'] ?? 'Unknown').toString(),
      graftsRequired: (graftsRaw is num) ? graftsRaw.toInt() : int.tryParse('$graftsRaw') ?? 0,
      confidenceScore: (confidenceRaw is num) ? confidenceRaw.toDouble() : double.tryParse('$confidenceRaw') ?? 0,
      treatmentSuggestions: List<String>.from(json['treatmentSuggestions'] ?? json['treatment_suggestions'] ?? const []),
      recommendationSummary: json['recommendationSummary']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'severityGrade': severityGrade,
        'graftsRequired': graftsRequired,
        'confidenceScore': confidenceScore,
        'treatmentSuggestions': treatmentSuggestions,
        'recommendationSummary': recommendationSummary,
      };
}
