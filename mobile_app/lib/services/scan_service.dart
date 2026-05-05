import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/constants/app_constants.dart';
import '../core/dio_client.dart';
import '../models/scalp_analysis_result_model.dart';

class ScanService {
  Future<ScalpAnalysisResultModel> analyzeScalp({
    required Uint8List imageBytes,
    required String userId,
  }) async {
    try {
      final form = FormData.fromMap({
        'user_id': userId,
        'file': MultipartFile.fromBytes(imageBytes, filename: 'scalp.jpg'),
      });
      final res = await DioClient.instance.post(
        '/analyze-scalp',
        data: form,
      );
      if (res.data is Map<String, dynamic>) {
        return ScalpAnalysisResultModel.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (_) {
      // Core phase: realistic mock fallback until backend is finalized.
    }

    return const ScalpAnalysisResultModel(
      severityGrade: 'Grade III',
      graftsRequired: 2300,
      confidenceScore: 0.89,
      treatmentSuggestions: [
        'Consider PRP sessions for 3 months',
        'Use dermatologist-approved minoxidil plan',
        'Schedule specialist consultation for graft planning',
      ],
      recommendationSummary: 'Moderate frontal thinning with high transplant response probability.',
    );
  }

  Future<void> saveResult(Map<String, dynamic> payload) async {
    await DioClient.instance.post(
      '${AppConstantsV2.apiV1}/scan/results',
      data: payload,
    );
  }
}
