import '../models/scalp_analysis_model.dart';

/// Default recommendations - shown when no analysis available
class RecommendationsData {
  static ScalpAnalysisModel get defaultAnalysis => ScalpAnalysisModel(
    id: '',
    userId: '',
    hairStrength: 72,
    scalpHealth: 60,
    hairDensity: 68,
    moistureLevel: 55,
    conditions: ['Complete a scalp analysis for personalized results'],
    recommendations: [
      'Use sulfate-free shampoo to maintain scalp health',
      'Apply natural oils (coconut, argan) 2-3 times per week',
      'Massage scalp for 5 minutes daily to improve circulation',
      'Stay hydrated - drink at least 8 glasses of water daily',
      'Consider biotin supplements for hair strength',
      'Avoid excessive heat styling',
      'Spend 3-5 minutes every night massaging your scalp',
      'Eat a balanced diet rich in protein, iron, and vitamins',
    ],
    createdAt: DateTime.now(),
  );
}
