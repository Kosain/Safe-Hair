import '../core/constants/app_constants.dart';
import '../core/dio_client.dart';
import '../models/consultant_model.dart';

class ConsultantService {
  Future<List<ConsultantModel>> fetchConsultants({
    int? maxBudget,
    String? location,
    String? specialization,
    double? minRating,
  }) async {
    final res = await DioClient.instance.get(
      '${AppConstantsV2.apiV1}/consultants',
      queryParameters: {
        if (maxBudget != null) 'max_budget': maxBudget,
        if (location != null && location.isNotEmpty) 'location': location,
        if (specialization != null && specialization.isNotEmpty) 'specialization': specialization,
        if (minRating != null) 'min_rating': minRating,
      },
    );
    final rows = (res.data is Map<String, dynamic>)
        ? List<Map<String, dynamic>>.from((res.data as Map<String, dynamic>)['consultants'] ?? const [])
        : <Map<String, dynamic>>[];
    return rows.map(ConsultantModel.fromJson).toList();
  }
}
