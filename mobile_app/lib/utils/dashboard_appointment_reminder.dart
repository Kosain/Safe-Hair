import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Lines for the dashboard reminder when the user has a future appointment.
typedef AppointmentReminderLines = ({String whenLine, String detailLine});

DateTime? _parseAppointmentStart(String dateIso, String timeSlot) {
  final parts = dateIso.trim().split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final mo = int.tryParse(parts[1]);
  final da = int.tryParse(parts[2]);
  if (y == null || mo == null || da == null) return null;

  final t = timeSlot.trim();
  final m12 = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)\b', caseSensitive: false).firstMatch(t);
  if (m12 != null) {
    var hour = int.parse(m12.group(1)!);
    final min = int.parse(m12.group(2)!);
    final ap = m12.group(3)!.toUpperCase();
    if (ap == 'PM' && hour != 12) hour += 12;
    if (ap == 'AM' && hour == 12) hour = 0;
    return DateTime(y, mo, da, hour, min);
  }

  final m24 = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
  if (m24 != null) {
    final hour = int.parse(m24.group(1)!);
    final min = int.parse(m24.group(2)!);
    return DateTime(y, mo, da, hour, min);
  }
  return null;
}

bool _appointmentActive(Map<String, dynamic> data) {
  final s = (data['status'] ?? 'confirmed').toString().toLowerCase();
  // Remind only after the doctor has confirmed (pending = waiting on doctor).
  if (s == 'pending') return false;
  return s != 'cancelled' && s != 'declined' && s != 'completed';
}

/// Picks the nearest upcoming appointment from Firestore `appointments` docs.
AppointmentReminderLines? nextUpcomingAppointmentSummary(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final now = DateTime.now();
  AppointmentReminderLines? best;
  DateTime? bestAt;

  for (final doc in docs) {
    final data = doc.data();
    if (!_appointmentActive(data)) continue;
    final dateIso = (data['date'] ?? data['day'] ?? '').toString();
    final timeSlot = (data['timeSlot'] ?? data['time_slot'] ?? '').toString();
    if (dateIso.isEmpty || timeSlot.isEmpty) continue;
    final at = _parseAppointmentStart(dateIso, timeSlot);
    if (at == null || !at.isAfter(now.subtract(const Duration(minutes: 1)))) continue;

    if (bestAt == null || at.isBefore(bestAt)) {
      bestAt = at;
      final doctor = (data['doctorName'] ?? 'Your doctor').toString().trim();
      final clinic = (data['clinicName'] ?? '').toString().trim();
      final whenLine = DateFormat('d MMM y, h:mm a').format(at);
      final detailLine = clinic.isNotEmpty ? 'Consultation with $doctor · $clinic' : 'Consultation with $doctor';
      best = (whenLine: whenLine, detailLine: detailLine);
    }
  }
  return best;
}
