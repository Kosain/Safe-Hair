import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';

class PatientAppointmentBookingScreen extends StatefulWidget {
  const PatientAppointmentBookingScreen({
    super.key,
    required this.doctorName,
    this.doctorId,
  });

  final String doctorName;
  final String? doctorId;

  @override
  State<PatientAppointmentBookingScreen> createState() => _PatientAppointmentBookingScreenState();
}

class _PatientAppointmentBookingScreenState extends State<PatientAppointmentBookingScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String? _selectedTime;
  String? _selectedReminder;

  static const _timeSlots = ['10:00 AM', '12:00 PM', '02:00 PM', '03:00 PM', '05:00 PM'];
  static const _reminders = ['20 Min', '25 Min', '30 Min', '35 Min', '40 Min'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAF6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
        ),
        title: const Text('Book Appointment', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE8E8E8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Doctor: ${widget.doctorName}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black),
                  ),
                  const SizedBox(height: 10),
                  TableCalendar(
                    firstDay: DateTime(2024, 1, 1),
                    lastDay: DateTime(2030, 12, 31),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (d) => _selectedDay != null && isSameDay(_selectedDay, d),
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                    },
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: false,
                    ),
                    daysOfWeekStyle: const DaysOfWeekStyle(
                      weekdayStyle: TextStyle(color: Colors.black),
                      weekendStyle: TextStyle(color: Colors.black),
                    ),
                    calendarStyle: CalendarStyle(
                      selectedDecoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                      selectedTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      todayDecoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE8E8E8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Available Time', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _timeSlots
                          .map(
                            (slot) => Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: _RoundOptionButton(
                                label: slot,
                                selected: _selectedTime == slot,
                                onTap: () => setState(() => _selectedTime = slot),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('Remind Me Before', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _reminders
                          .map(
                            (slot) => Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: _RoundOptionButton(
                                label: slot,
                                selected: _selectedReminder == slot,
                                onTap: () => setState(() => _selectedReminder = slot),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: SizedBox(
                      width: 220,
                      child: ElevatedButton(
                        onPressed: _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF176),
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Confirm Appointment', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirm() {
    if (_selectedDay == null || _selectedTime == null || _selectedReminder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select date, time and reminder before confirming.')),
      );
      return;
    }
    final dateLabel = '${_selectedDay!.day}/${_selectedDay!.month}/${_selectedDay!.year}';
    _showSuccessDialog(dateLabel, _selectedTime!);
  }

  void _showSuccessDialog(String dateLabel, String timeLabel) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Success',
      barrierColor: Colors.black.withValues(alpha: 0.24),
      pageBuilder: (ctx, a1, a2) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FCF8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 86,
                      height: 86,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2D3238),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.thumb_up, color: Colors.white, size: 38),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Thank You !',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E1E1E)),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Your Appointment Successful',
                      style: TextStyle(fontSize: 14, color: Color(0xFF6A6A6A), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You booked an appointment with ${widget.doctorName} on $dateLabel at $timeLabel',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6A6A6A), height: 1.3),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 120,
                      height: 32,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          context.go('/my-appointments');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF176),
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: const Size(120, 32),
                        ),
                        child: const Text('Done', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text(
                        'Edit your appointment',
                        style: TextStyle(
                          color: Color(0xFF6A6A6A),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RoundOptionButton extends StatelessWidget {
  const _RoundOptionButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.black : const Color(0xFFBDBDBD),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
