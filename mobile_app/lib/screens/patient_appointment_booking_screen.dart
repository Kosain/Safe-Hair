import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../core/safe_hair_colors.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
import '../utils/doctor_availability_slots.dart';
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
  Map<String, DoctorDayAvailability> _weeklyAvailability = {};
  List<String> _openSlots = [];
  List<String> _reminderOptions = const ['20 Min', '25 Min', '30 Min', '35 Min', '40 Min'];
  String? _slotsMessage;
  bool _loadingDoctor = true;
  bool _loadingSlots = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDoctorSchedule());
  }

  String _dateIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isPastDay(DateTime day) => _dateOnly(day).isBefore(_dateOnly(DateTime.now()));

  bool _isDayEnabled(DateTime day) {
    final d = _dateOnly(day);
    if (d.isBefore(_dateOnly(DateTime.now()))) return false;
    final av = _weeklyAvailability[weekdayKeyFromDate(day)];
    return av != null && av.available;
  }

  DateTime? _firstEnabledDayFrom(DateTime from) {
    final start = _dateOnly(from);
    for (var i = 0; i < 370; i++) {
      final d = start.add(Duration(days: i));
      if (_isDayEnabled(d)) return d;
    }
    return null;
  }

  Future<void> _loadDoctorSchedule() async {
    if (widget.doctorId == null || widget.doctorId!.isEmpty || !FirebaseService.isInitialized) {
      if (mounted) setState(() => _loadingDoctor = false);
      return;
    }
    setState(() => _loadingDoctor = true);
    try {
      final profile = await FirebaseService.getDoctorProfile(widget.doctorId!);
      final weekly = parseDoctorAvailability(profile);
      final reminders = reminderLabelsFromDoctorProfile(profile);
      if (!mounted) return;
      setState(() {
        _weeklyAvailability = weekly;
        _reminderOptions = reminders;
        _selectedReminder ??= reminders.isNotEmpty ? reminders.first : null;
        if (weekly.isEmpty) {
          _slotsMessage = 'This doctor has not set weekly hours yet. Ask them to complete availability in registration.';
        }
        final first = _firstEnabledDayFrom(DateTime.now());
        if (first != null) {
          _selectedDay = first;
          _focusedDay = first;
        }
      });
      await _refreshBookedSlots();
    } finally {
      if (mounted) setState(() => _loadingDoctor = false);
    }
  }

  Future<void> _refreshBookedSlots() async {
    if (widget.doctorId == null || widget.doctorId!.isEmpty || _selectedDay == null) {
      if (mounted) {
        setState(() {
          _openSlots = [];
          _slotsMessage = null;
        });
      }
      return;
    }

    setState(() => _loadingSlots = true);
    try {
      final day = _selectedDay!;
      final allForDay = hourlySlotsForDate(_weeklyAvailability, day);
      if (allForDay.isEmpty) {
        if (mounted) {
          setState(() {
            _openSlots = [];
            _selectedTime = null;
            _slotsMessage = 'Doctor is not available on this day. Please choose another date.';
          });
        }
        return;
      }

      final iso = _dateIso(day);
      final bookedRaw = FirebaseService.isInitialized
          ? await FirebaseService.getBookedTimeSlotsForDoctorDate(doctorId: widget.doctorId!, date: iso)
          : <String>{};
      final booked = normalizeSlotLabelSet(bookedRaw);

      final open = allForDay.where((t) => !booked.contains(normalizeSlotLabel(t))).toList();

      if (mounted) {
        setState(() {
          _openSlots = open;
          if (open.isEmpty) {
            _selectedTime = null;
            _slotsMessage = 'No time slot available on the date you selected.';
          } else {
            _slotsMessage = null;
            if (_selectedTime == null || !open.contains(_selectedTime)) {
              _selectedTime = open.first;
            }
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
    if (_openSlots.isEmpty || !_openSlots.contains(_selectedTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No available time slot for this date.')),
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
    final sh = context.sh;
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
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: sh.textPrimary),
              ),
              Expanded(
                child: Text(
                  'Book appointment',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: sh.textPrimary),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 4),
          if (_loadingDoctor)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator(color: sh.textPrimary)),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: sh.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: sh.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.doctorName,
                    style: TextStyle(fontWeight: FontWeight.w700, color: sh.textPrimary, fontSize: 16),
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(sub, style: TextStyle(fontSize: 13, color: sh.textSecondary)),
                  ],
                  if (widget.consultationFeePkr != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Consultation fee: PKR ${widget.consultationFeePkr}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sh.textPrimary),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TableCalendar(
                    firstDay: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
                    lastDay: DateTime(2030, 12, 31),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (d) => _selectedDay != null && isSameDay(_selectedDay, d),
                    onDaySelected: (selectedDay, focusedDay) {
                      if (_isPastDay(selectedDay)) return;
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                      _refreshBookedSlots();
                    },
                    onPageChanged: (focusedDay) {
                      setState(() => _focusedDay = focusedDay);
                    },
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: false,
                      titleTextStyle: TextStyle(color: sh.textPrimary, fontWeight: FontWeight.w600),
                      leftChevronIcon: Icon(Icons.chevron_left, color: sh.textPrimary),
                      rightChevronIcon: Icon(Icons.chevron_right, color: sh.textPrimary),
                    ),
                    daysOfWeekStyle: DaysOfWeekStyle(
                      weekdayStyle: TextStyle(color: sh.textSecondary, fontWeight: FontWeight.w600),
                      weekendStyle: TextStyle(color: sh.textSecondary, fontWeight: FontWeight.w600),
                    ),
                    calendarStyle: CalendarStyle(
                      defaultTextStyle: TextStyle(color: sh.textPrimary),
                      weekendTextStyle: TextStyle(color: sh.textPrimary),
                      outsideTextStyle: TextStyle(color: sh.textSecondary.withValues(alpha: 0.5)),
                      disabledTextStyle: TextStyle(color: sh.textSecondary.withValues(alpha: 0.35)),
                      selectedDecoration: BoxDecoration(color: sh.selectedNavBg, shape: BoxShape.circle),
                      selectedTextStyle: TextStyle(color: sh.selectedNavFg, fontWeight: FontWeight.w700),
                      todayDecoration: BoxDecoration(
                        color: sh.sidebarSelectedBg,
                        shape: BoxShape.circle,
                      ),
                      todayTextStyle: TextStyle(color: sh.textPrimary, fontWeight: FontWeight.w600),
                    ),
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (context, day, focusedDay) {
                        if (_isPastDay(day)) return null;
                        final enabled = _isDayEnabled(day);
                        return Center(
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              color: enabled ? sh.textPrimary : sh.textSecondary.withValues(alpha: 0.45),
                              fontWeight: enabled ? FontWeight.w500 : FontWeight.w400,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_loadingSlots)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: sh.textPrimary),
                          ),
                          const SizedBox(width: 8),
                          Text('Checking availability…', style: TextStyle(fontSize: 12, color: sh.textSecondary)),
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
                color: sh.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: sh.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Available time', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: sh.textPrimary)),
                  const SizedBox(height: 12),
                  if (_openSlots.isEmpty && !_loadingSlots)
                    Text(
                      _slotsMessage ?? 'Select a date to see available times.',
                      style: TextStyle(fontSize: 13, color: sh.textSecondary, height: 1.35),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _openSlots.map((slot) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: _RoundOptionButton(
                              sh: sh,
                              label: slot,
                              selected: _selectedTime == slot,
                              enabled: true,
                              onTap: () => setState(() => _selectedTime = slot),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Text('Remind me before', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: sh.textPrimary)),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _reminderOptions
                          .map(
                            (slot) => Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: _RoundOptionButton(
                                sh: sh,
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
                        onPressed: _saving || _openSlots.isEmpty ? null : _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF176),
                          foregroundColor: Colors.black87,
                          disabledBackgroundColor: sh.sidebarSelectedBg,
                          disabledForegroundColor: sh.textSecondary,
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
        ],
      ),
    );
  }
}

class _RoundOptionButton extends StatelessWidget {
  const _RoundOptionButton({
    required this.sh,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final SafeHairColors sh;
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
            color: selected ? sh.selectedNavBg : sh.scaffold,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? sh.selectedNavBg : sh.border,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? sh.selectedNavFg : sh.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
