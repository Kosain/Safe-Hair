import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import '../core/nav_helper.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';

class AppointmentScreen extends StatefulWidget {
  final String? doctorId;
  final String? doctorName;
  final String? clinicName;

  const AppointmentScreen({super.key, this.doctorId, this.doctorName, this.clinicName});

  @override
  State<AppointmentScreen> createState() => _AppointmentScreenState();
}

class _AppointmentScreenState extends State<AppointmentScreen> {
  DateTime _selectedDate = DateTime.now();
  String? _selectedTime;
  String? _selectedReminder;
  final _consultationNotesController = TextEditingController();
  bool _loading = false;
  bool _loadingSlots = false;
  List<String> _availableTimeSlots = List<String>.from(AppConstants.timeSlots);
  /// Parsed from Firestore `availabilityWeekly` when present. Empty => use default slot list for all days.
  Map<String, List<String>> _weeklyClinicSlots = {};
  String? _slotsHelpText;
  int? _consultationFee;
  String? _generalTimingText;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get _usesClinicWeekly => _weeklyClinicSlots.isNotEmpty;

  String _dayKey(DateTime d) {
    switch (d.weekday) {
      case DateTime.monday:
        return 'Mon';
      case DateTime.tuesday:
        return 'Tue';
      case DateTime.wednesday:
        return 'Wed';
      case DateTime.thursday:
        return 'Thu';
      case DateTime.friday:
        return 'Fri';
      case DateTime.saturday:
        return 'Sat';
      default:
        return 'Sun';
    }
  }

  Map<String, List<String>> _parseWeeklyAvailability(dynamic raw) {
    if (raw is! Map) return {};
    final out = <String, List<String>>{};
    raw.forEach((k, v) {
      final key = k.toString();
      if (v is List) {
        out[key] = v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
    });
    return out;
  }

  bool _isClinicOpenOn(DateTime day) {
    if (!_usesClinicWeekly) return true;
    final slots = _weeklyClinicSlots[_dayKey(day)];
    return slots != null && slots.isNotEmpty;
  }

  bool _isCalendarDayEnabled(DateTime day) {
    final d = _dateOnly(day);
    final today = _dateOnly(DateTime.now());
    if (d.isBefore(today)) return false;
    return _isClinicOpenOn(day);
  }

  DateTime? _firstBookableDayFrom(DateTime from) {
    final start = _dateOnly(from);
    for (var i = 0; i < 370; i++) {
      final d = start.add(Duration(days: i));
      if (_isCalendarDayEnabled(d)) return d;
    }
    return null;
  }

  Future<void> _loadClinicWeeklyFromFirestore() async {
    final doctorId = widget.doctorId?.trim();
    if (doctorId == null || doctorId.isEmpty) {
      if (mounted) {
        setState(() => _weeklyClinicSlots = {});
      }
      return;
    }

    int? fee;
    // Only query backend when Firebase is unavailable.
    if (!FirebaseService.isInitialized) {
      try {
        final doctors = await ApiService().getDoctors();
        final match = doctors.firstWhere((d) => d['id'].toString() == doctorId, orElse: () => {});
        if (match.isNotEmpty) {
          final feeRaw = match['consultationFee'] ?? match['consultation_fee'];
          if (feeRaw != null) fee = int.tryParse(feeRaw.toString());
        }
      } catch (_) {}
    }

    if (!FirebaseService.isInitialized) {
      if (mounted) setState(() { _weeklyClinicSlots = {}; _consultationFee = fee; });
      return;
    }

    try {
      final profile = await FirebaseService.getDoctorProfile(doctorId);
      final parsed = _parseWeeklyAvailability(profile?['availabilityWeekly']);
      if (profile != null) {
        final feeRaw = profile['consultationFee'] ?? profile['consultation_fee'];
        if (feeRaw != null) {
          fee = int.tryParse(feeRaw.toString()) ?? fee;
        }
      }
      // Calculate a brief timing summary
      String? timingSummary;
      if (parsed.isNotEmpty) {
        final days = parsed.keys.toList();
        if (days.isNotEmpty) {
          timingSummary = 'Open: ${days.join(", ")}';
        }
      }

      if (mounted) {
        setState(() {
          _weeklyClinicSlots = parsed;
          _consultationFee = fee;
          _generalTimingText = timingSummary;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _weeklyClinicSlots = {}; _consultationFee = fee; });
    }
  }

  void _ensureSelectedDateMatchesClinic() {
    if (!_usesClinicWeekly) return;
    if (_isCalendarDayEnabled(_selectedDate)) return;
    final next = _firstBookableDayFrom(DateTime.now());
    if (next != null) {
      setState(() => _selectedDate = next);
    }
  }

  Future<void> _refreshSlotsForSelectedDate() async {
    final doctorId = widget.doctorId?.trim();

    setState(() {
      _loadingSlots = true;
      _slotsHelpText = null;
    });

    try {
      List<String> baseSlots;
      if (_usesClinicWeekly) {
        baseSlots = List<String>.from(_weeklyClinicSlots[_dayKey(_selectedDate)] ?? []);
        if (baseSlots.isEmpty) {
          if (mounted) {
            setState(() {
              _availableTimeSlots = [];
              _selectedTime = null;
              _slotsHelpText = 'This clinic is closed on ${_dayKey(_selectedDate)}. Choose another day.';
            });
          }
          return;
        }
      } else {
        baseSlots = List<String>.from(AppConstants.timeSlots);
      }

      Set<String> booked = {};
      if (doctorId != null && doctorId.isNotEmpty && FirebaseService.isInitialized) {
        final dateStr =
            '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
        booked = await FirebaseService.getBookedTimeSlotsForDoctorDate(
          doctorId: doctorId,
          date: dateStr,
        );
      }

      final open = baseSlots.where((t) => !booked.contains(t)).toList();

      if (mounted) {
        setState(() {
          _availableTimeSlots = open;
          if (open.isEmpty) {
            _selectedTime = null;
            _slotsHelpText = baseSlots.isNotEmpty
                ? 'All listed times are already booked for this date. Try another day or time.'
                : 'No time slots available.';
          } else {
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

  Future<void> _onCalendarDaySelected(DateTime selected, DateTime _) async {
    setState(() {
      _selectedDate = selected;
    });
    await _refreshSlotsForSelectedDate();
  }

  Future<void> _initScheduling() async {
    await _loadClinicWeeklyFromFirestore();
    if (!mounted) return;
    _ensureSelectedDateMatchesClinic();
    if (!mounted) return;
    await _refreshSlotsForSelectedDate();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initScheduling());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.primaryGreen,
      appBar: AppBar(
        backgroundColor: AppColors.primaryGreen,
        elevation: 0,
        leading: IconButton(
          onPressed: () => backOrGo(context, '/doctors'),
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textDark),
        ),
        title: Text('Appointment', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.cardBackground.withOpacity(0.45),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.55)),
              ),
              child: Text('Appointment', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.cardBackground.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.doctorName ?? 'Doctor',
                    style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if ((widget.clinicName ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.local_hospital, size: 14, color: AppColors.textGrey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.clinicName!,
                            style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_generalTimingText != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 14, color: AppColors.textGrey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _generalTimingText!,
                            style: TextStyle(color: AppColors.textDark, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_consultationFee != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.payments_outlined, size: 14, color: AppColors.textGrey),
                        const SizedBox(width: 4),
                        Text(
                          'Fee: Rs ${_consultationFee}',
                          style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.6)),
              ),
              child: TableCalendar(
                firstDay: DateTime.now(),
                lastDay: DateTime.now().add(const Duration(days: 365)),
                focusedDay: _selectedDate,
                selectedDayPredicate: (d) => isSameDay(d, _selectedDate),
                onDaySelected: _onCalendarDaySelected,
                enabledDayPredicate: _isCalendarDayEnabled,
                calendarFormat: CalendarFormat.month,
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: false,
                  leftChevronIcon: const Icon(Icons.chevron_left, color: AppColors.textDark),
                  rightChevronIcon: const Icon(Icons.chevron_right, color: AppColors.textDark),
                  titleTextStyle: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: AppColors.textDark),
                ),
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(color: Colors.black.withOpacity(0.18), shape: BoxShape.circle),
                  selectedDecoration: const BoxDecoration(color: AppColors.darkButton, shape: BoxShape.circle),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardBackground.withOpacity(0.45),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.55)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Available Time', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                  if (_usesClinicWeekly) ...[
                    const SizedBox(height: 6),
                    Text(
                      "Times follow this clinic's registered schedule. Greyed-out dates are closed.",
                      style: TextStyle(fontSize: 12, color: AppColors.textGrey, height: 1.3),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_loadingSlots)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_availableTimeSlots.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _slotsHelpText ?? 'No times to show.',
                        style: TextStyle(fontSize: 14, color: AppColors.textDark, height: 1.35),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _availableTimeSlots.map((t) {
                        final selected = _selectedTime == t;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedTime = t),
                          child: Container(
                            width: 70,
                            height: 70,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected ? AppColors.darkButton : AppColors.textGrey.withOpacity(0.9),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              t,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 20),
                  Text('Remind Me Before', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: AppConstants.reminderOptions.map((r) {
                      final selected = _selectedReminder == r;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedReminder = r),
                        child: Container(
                          width: 70,
                          height: 70,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected ? AppColors.darkButton : AppColors.textGrey.withOpacity(0.9),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            r,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (_selectedTime != null &&
                              _selectedReminder != null &&
                              !_loading &&
                              !_loadingSlots &&
                              _availableTimeSlots.isNotEmpty)
                          ? _confirmAppointment
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFF176),
                        foregroundColor: Colors.black87,
                        disabledBackgroundColor: Colors.grey.shade400,
                        disabledForegroundColor: Colors.grey.shade600,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                            )
                          : const Text('Confirm', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAppointment() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.userId ?? 'unknown';

    late final String doctorId;
    final doctorName = widget.doctorName ?? 'Dr. Pediatrician Purpieson';
    if (FirebaseService.isInitialized) {
      final id = widget.doctorId?.trim();
      if (id == null || id.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Missing doctor id. Go back and choose a doctor from the live list so bookings reach the right account.'),
          ),
        );
        return;
      }
      doctorId = id;
    } else {
      doctorId = widget.doctorId ?? '1';
    }
    final reminderMin = int.tryParse(_selectedReminder!.replaceAll(RegExp(r'[^0-9]'), '')) ?? 30;

    setState(() => _loading = true);

    final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    final notes = _consultationNotesController.text.trim();

    String? patientName;
    if (FirebaseService.isInitialized) {
      final pd = await FirebaseService.getPatientDetails(userId);
      final row = pd?.data();
      if (row != null) {
        final n = row['name']?.toString().trim();
        final fn = row['fullName']?.toString().trim();
        if (n != null && n.isNotEmpty) {
          patientName = n;
        } else if (fn != null && fn.isNotEmpty) {
          patientName = fn;
        }
      }
    }
    if (!mounted) return;
    if (patientName == null || patientName.isEmpty) {
      final authName = auth.userName?.trim();
      if (authName != null && authName.isNotEmpty) {
        patientName = authName;
      } else {
        final dn = FirebaseService.auth.currentUser?.displayName?.trim();
        if (dn != null && dn.isNotEmpty) patientName = dn;
      }
    }
    final priority = notes.toLowerCase().contains('urgent') ? 'urgent' : 'normal';

    // Prevent double-booking for the same doctor/date/time.
    final alreadyBooked = await FirebaseService.isAppointmentSlotBooked(
      doctorId: doctorId,
      date: dateStr,
      timeSlot: _selectedTime!,
    );
    if (alreadyBooked) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selected slot is already booked. Please pick another time.')));
      return;
    }

    final data = {
      'userId': userId,
      'doctorId': doctorId,
      'doctorName': doctorName,
      'clinicName': widget.clinicName,
      'date': dateStr,
      'timeSlot': _selectedTime!,
      'reminderMinutes': reminderMin,
      'consultationNotes': notes.isEmpty ? null : notes,
      'status': 'pending',
      'priority': priority,
      'createdAt': DateTime.now().toIso8601String(),
      if (patientName != null && patientName.isNotEmpty) 'patientName': patientName,
    };

    if (!FirebaseService.isInitialized) {
      await ApiService().createAppointment(
        userId: userId,
        doctorId: doctorId,
        doctorName: doctorName,
        date: dateStr,
        timeSlot: _selectedTime!,
        reminderMinutes: reminderMin,
        consultationNotes: notes.isEmpty ? null : notes,
        patientName: patientName,
        priority: priority,
      );
    }
    if (FirebaseService.isInitialized) {
      await FirebaseService.saveAppointment(data);
      await FirebaseService.saveReport({
        'userId': userId,
        'type': 'consultation',
        'title': 'Consultation with ${widget.doctorName ?? doctorName}',
        'doctorName': doctorName,
        'date': dateStr,
        'createdAt': DateTime.now().toIso8601String(),
        'summary': {'date': dateStr, 'time': _selectedTime, 'notes': notes},
        'recommendations': [],
      });
    }

    if (mounted) {
      setState(() => _loading = false);
      _showSuccessDialog(doctorName);
    }
  }

  void _showSuccessDialog(String doctorName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(color: AppColors.darkButton, shape: BoxShape.circle),
              child: const Icon(Icons.thumb_up, color: AppColors.white, size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              'Thank You!',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your Appointment Successful',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textGrey,
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'You booked an appointment with $doctorName on ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}, at $_selectedTime',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textDark,
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 140,
              height: 40,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFF176),
                  foregroundColor: Colors.black87,
                  minimumSize: const Size(140, 40),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  context.go('/dashboard');
                },
                child: const Text('Done', style: TextStyle(fontSize: 12)),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
              },
              child: Text(
                'Edit your appointment',
                style: TextStyle(color: AppColors.textGrey, fontSize: 12, decoration: TextDecoration.none),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
