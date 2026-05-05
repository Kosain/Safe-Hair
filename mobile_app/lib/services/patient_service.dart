import '../core/constants/app_constants.dart';
import '../core/dio_client.dart';
import '../models/patient_model.dart';

class PatientService {
  Future<void> saveOnboardingData(PatientModel patient) async {
    await DioClient.instance.post(
      '${AppConstantsV2.apiV1}/patients/onboarding',
      data: patient.toJson(),
    );
  }

  Future<PatientModel?> getPatientProfile(String userId) async {
    final res = await DioClient.instance.get(
      '${AppConstantsV2.apiV1}/patients/$userId',
    );
    if (res.data is Map<String, dynamic>) {
      return PatientModel.fromJson(res.data as Map<String, dynamic>);
    }
    return null;
  }
}
