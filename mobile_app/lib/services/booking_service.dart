import '../core/constants/app_constants.dart';
import '../core/dio_client.dart';
import '../models/booking_slot_model.dart';

class BookingService {
  Future<List<String>> fetchAvailableSlots({
    required String consultantId,
    required DateTime date,
  }) async {
    final res = await DioClient.instance.get(
      '${AppConstantsV2.apiV1}/consultants/$consultantId/slots',
      queryParameters: {'date': date.toIso8601String()},
    );
    if (res.data is Map<String, dynamic>) {
      return List<String>.from((res.data as Map<String, dynamic>)['slots'] ?? const []);
    }
    return const [];
  }

  Future<void> bookAppointment({
    required String patientId,
    required BookingSlotModel slot,
    String? notes,
  }) async {
    await DioClient.instance.post(
      '${AppConstantsV2.apiV1}/appointments',
      data: {
        'patient_id': patientId,
        ...slot.toJson(),
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
  }
}
