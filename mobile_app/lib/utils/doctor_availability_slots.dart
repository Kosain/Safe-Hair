import 'package:intl/intl.dart';

/// One weekday row from `doctors/{id}.availability`.
class DoctorDayAvailability {
  const DoctorDayAvailability({
    required this.available,
    required this.startMinutes,
    required this.endMinutes,
  });

  final bool available;
  final int startMinutes;
  final int endMinutes;
}

String weekdayKeyFromDate(DateTime d) {
  switch (d.weekday) {
    case DateTime.monday:
      return 'monday';
    case DateTime.tuesday:
      return 'tuesday';
    case DateTime.wednesday:
      return 'wednesday';
    case DateTime.thursday:
      return 'thursday';
    case DateTime.friday:
      return 'friday';
    case DateTime.saturday:
      return 'saturday';
    default:
      return 'sunday';
  }
}

int? _parseHHmmToMinutes(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final parts = s.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0].trim());
  final m = int.tryParse(parts[1].trim());
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

/// Reads `availability` map saved during doctor registration.
Map<String, DoctorDayAvailability> parseDoctorAvailability(Map<String, dynamic>? profile) {
  final raw = profile?['availability'];
  if (raw is! Map) return {};
  final out = <String, DoctorDayAvailability>{};
  raw.forEach((key, value) {
    if (value is! Map) return;
    final available = value['available'] == true;
    if (!available) {
      out[key.toString().toLowerCase()] = const DoctorDayAvailability(
        available: false,
        startMinutes: 0,
        endMinutes: 0,
      );
      return;
    }
    final start = _parseHHmmToMinutes((value['start'] ?? '').toString());
    final end = _parseHHmmToMinutes((value['end'] ?? '').toString());
    if (start == null || end == null || end <= start) return;
    out[key.toString().toLowerCase()] = DoctorDayAvailability(
      available: true,
      startMinutes: start,
      endMinutes: end,
    );
  });
  return out;
}

/// Hourly labels from start (rounded down to hour) through one hour before [endMinutes].
List<String> generateHourlySlotLabels(int startMinutes, int endMinutes) {
  final lastSlotStart = endMinutes - 60;
  if (lastSlotStart < startMinutes) return [];

  var cursor = (startMinutes ~/ 60) * 60;
  final slots = <String>[];
  final fmt = DateFormat('h:mm a');

  while (cursor <= lastSlotStart) {
    final h = cursor ~/ 60;
    final m = cursor % 60;
    slots.add(fmt.format(DateTime(2000, 1, 1, h, m)));
    cursor += 60;
  }
  return slots;
}

List<String> hourlySlotsForDate(
  Map<String, DoctorDayAvailability> weekly,
  DateTime day,
) {
  final dayAv = weekly[weekdayKeyFromDate(day)];
  if (dayAv == null || !dayAv.available) return [];
  return generateHourlySlotLabels(dayAv.startMinutes, dayAv.endMinutes);
}

/// Normalizes labels so "2:00 PM" and "02:00 PM" compare equal.
String normalizeSlotLabel(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return s;
  try {
    final parsed = DateFormat('h:mm a').parse(s);
    return DateFormat('h:mm a').format(parsed);
  } catch (_) {
    return s;
  }
}

Set<String> normalizeSlotLabelSet(Iterable<String> labels) {
  return labels.map(normalizeSlotLabel).toSet();
}

List<String> reminderLabelsFromDoctorProfile(Map<String, dynamic>? profile) {
  const defaults = [20, 25, 30, 35, 40];
  final raw = profile?['remindMeBeforeMinutes'];
  if (raw is int && raw > 0) {
    return ['$raw Min'];
  }
  if (raw is num && raw > 0) {
    return ['${raw.toInt()} Min'];
  }
  return defaults.map((m) => '$m Min').toList();
}
