import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
import '../widgets/patient_web_scaffold.dart';

class PatientAppointmentBookingScreen extends StatefulWidget {
  const PatientAppointmentBookingScreen({
    super.key,
    required this.doctorName,
    this.doctorId,
    this.clinicName,
    this.city,
    this.consultationFeePkr,
  });

  final String doctorName;
  final String? doctorId;
  final String? clinicName;
  final String? city;
  final int? consultationFeePkr;

  @override
  State<PatientAppointmentBookingScreen> createState() => _PatientAppointmentBookingScreenState();
}

class _PatientAppointmentBookingScreenState extends State<PatientAppointmentBookingScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String? _selectedTime;
  String? _selectedReminder;
  Set<String> _bookedSlots = {};
  bool _loadingSlots = false;
  bool _saving = false;

  static const _timeSlots = ['10:00 AM', '12:00 PM', '02:00 PM', '03:00 PM', '05:00 PM'];
  static const _reminders = ['20 Min', '25 Min', '30 Min', '35 Min', '40 Min'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshBookedSlots());
  }

  String _dateIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _refreshBookedSlots() async {
    if (widget.doctorId == null || widget.doctorId!.isEmpty || _selectedDay == null) {
      if (mounted) setState(() => _bookedSlots = {});
      return;
    }
    if (!FirebaseService.isInitialized) return;
    setState(() => _loadingSlots = true);
    try {
      final iso = _dateIso(_selectedDay!);
      final s = await FirebaseService.getBookedTimeSlotsForDoctorDate(doctorId: widget.doctorId!, date: iso);
      if (mounted) {
        setState(() {
          _bookedSlots = s;
          if (_selectedTime != null && _bookedSlots.contains(_selectedTime)) {
            _selectedTime = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  int? _reminderMinutes(String? label) {
    if (label == null) return null;
    final m = RegExp(r'(\d+)').firstMatch(label);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  Future<void> _confirm() async {
    if (_selectedDay == null || _selectedTime == null || _selectedReminder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select date, time, and reminder before confirming.')),
      );
      return;
    }
    final uid = context.read<AuthProvider>().userId;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to save this booking to your account.')),
      );
      return;
    }
    if (widget.doctorId == null || widget.doctorId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing doctor id; cannot reserve this slot.')),
      );
      return;
    }

    final dateIso = _dateIso(_selectedDay!);
    final time = _selectedTime!;
    final reminder = _reminderMinutes(_selectedReminder);
    final patientLabel = context.read<AuthProvider>().userName?.trim();

    if (FirebaseService.isInitialized) {
      final taken = await FirebaseService.isAppointmentSlotBooked(
        doctorId: widget.doctorId!,
        date: dateIso,
        timeSlot: time,
      );
      if (taken && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That time was just taken. Pick another slot.')),
        );
        await _refreshBookedSlots();
        return;
      }
    }

    setState(() => _saving = true);
    try {
      if (FirebaseService.isInitialized) {
        final id = await FirebaseService.saveAppointment({
          'userId': uid,
          'doctorId': widget.doctorId,
          'doctorName': widget.doctorName,
          'clinicName': widget.clinicName,
          'city': widget.city,
          'date': dateIso,
          'timeSlot': time,
          'reminderMinutes': reminder ?? 30,
          'status': 'pending',
          if (patientLabel != null && patientLabel.isNotEmpty) 'patientName': patientLabel,
          'consultationFeePkr': widget.consultationFeePkr,
          'createdAt': DateTime.now().toIso8601String(),
        });
        if (id == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save appointment. Check Firebase rules and connection.')),
          );
          return;
        }
      }

      if (!mounted) return;
      final dateLabel = '${_selectedDay!.day}/${_selectedDay!.month}/${_selectedDay!.year}';
      context.go(
        '/my-appointments/success',
        extra: {
          'doctorName': widget.doctorName,
          'doctorId': widget.doctorId,
          'date': dateLabel,
          'time': time,
          'reminder': _selectedReminder,
        },
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = [widget.clinicName, widget.city].where((e) => (e ?? '').trim().isNotEmpty).join(' • ');
    final route = GoRouterState.of(context).matchedLocation;
    return PatientWebScaffold(
      currentRoute: route,
      extraScrollBottomPadding: 80,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
              ),
              const Expanded(
                child: Text(
                  'Book appointment',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 4),
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
                    widget.doctorName,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black, fontSize: 16),
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(sub, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                  ],
                  if (widget.consultationFeePkr != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Consultation fee: PKR ${widget.consultationFeePkr}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TableCalendar(
                    firstDay: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
                    lastDay: DateTime(2030, 12, 31),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (d) => _selectedDay != null && isSameDay(_selectedDay, d),
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                      _refreshBookedSlots();
                    },
                    onPageChanged: (focusedDay) {
                      _focusedDay = focusedDay;
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
                  if (_loadingSlots)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey.shade600)),
                          const SizedBox(width: 8),
                          Text('Checking availability…', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        ],
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
                  const Text('Available time', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _timeSlots.map((slot) {
                        final booked = _bookedSlots.contains(slot);
                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: _RoundOptionButton(
                            label: booked ? '$slot (taken)' : slot,
                            selected: _selectedTime == slot && !booked,
                            enabled: !booked,
                            onTap: booked ? () {} : () => setState(() => _selectedTime = slot),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('Remind me before', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
                                enabled: true,
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
                      width: 260,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF176),
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                              )
                            : const Text('Confirm appointment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
      ),
    );
  }
}

class _RoundOptionButton extends StatelessWidget {
  const _RoundOptionButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              color: selected ? Colors.white : (enabled ? Colors.black : Colors.grey),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
