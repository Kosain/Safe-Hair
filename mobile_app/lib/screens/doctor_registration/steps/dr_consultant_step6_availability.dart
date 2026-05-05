import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_colors.dart';
import '../../../providers/doctor_registration_provider.dart';
import '../consultant_registration_ui.dart';
import '../doctor_registration_constants.dart';

class DrConsultantStep6Availability extends StatelessWidget {
  const DrConsultantStep6Availability({super.key});

  static const _weekdays = kConsultantWeekdays;

  Future<TimeOfDay?> _pickTime(BuildContext context, TimeOfDay initial) {
    return showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Colors.black,
              hourMinuteColor: const Color(0xFF1A1A1A),
              hourMinuteTextColor: Colors.white,
              dayPeriodColor: Colors.grey.shade300,
              dayPeriodTextColor: Colors.black,
              dialBackgroundColor: const Color(0xFF202020),
              dialTextColor: Colors.white,
              dialTextStyle: const TextStyle(color: Colors.white),
              dialHandColor: Colors.black,
              entryModeIconColor: Colors.white,
              confirmButtonStyle: ButtonStyle(
                foregroundColor: WidgetStateProperty.all(Colors.white),
              ),
              cancelButtonStyle: ButtonStyle(
                foregroundColor: WidgetStateProperty.all(Colors.white),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DoctorRegistrationProvider>(
      builder: (context, p, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: consultantCardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weekly schedule',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textDark, letterSpacing: -0.3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Turn on the days you consult. Set your working hours for each day.',
                      style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.textGrey.withValues(alpha: 0.92)),
                    ),
                    const SizedBox(height: 18),
                    ..._weekdays.map((day) {
                      final slot = p.daySchedules[day]!;
                      final err = p.fieldErrors[day];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FB),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  weekdayTitle(day),
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black),
                                ),
                                value: slot.available,
                                thumbColor: const WidgetStatePropertyAll<Color>(Colors.white),
                                trackColor: WidgetStateProperty.resolveWith<Color>((states) {
                                  if (states.contains(WidgetState.selected)) return Colors.black;
                                  return Colors.black.withValues(alpha: 0.65);
                                }),
                                onChanged: (v) {
                                  slot.available = v;
                                  p.refresh();
                                },
                              ),
                              if (slot.available)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _TimeAction(
                                      label: 'Start',
                                      time: slot.start,
                                      onTap: () async {
                                        final t = await _pickTime(context, slot.start ?? const TimeOfDay(hour: 9, minute: 0));
                                        if (t != null) {
                                          slot.start = t;
                                          p.refresh();
                                        }
                                      },
                                    ),
                                    _TimeAction(
                                      label: 'End',
                                      time: slot.end,
                                      onTap: () async {
                                        final t = await _pickTime(context, slot.end ?? const TimeOfDay(hour: 17, minute: 0));
                                        if (t != null) {
                                          slot.end = t;
                                          p.refresh();
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              if (err != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(err, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimeAction extends StatelessWidget {
  const _TimeAction({
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final TimeOfDay? time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = time == null ? '—' : time!.format(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        side: BorderSide(color: AppColors.textDark.withValues(alpha: 0.2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        '$label time: $t',
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.black),
      ),
    );
  }
}
