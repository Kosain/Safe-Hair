import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/safe_hair_colors.dart';
import '../l10n/app_translations.dart';
import '../l10n/tr.dart';
import '../providers/auth_provider.dart';
import '../services/chat_service.dart';
import '../services/firebase_service.dart';
import 'doctor_patient_clinical_page.dart';

class _PendingRequest {
  const _PendingRequest({
    required this.id,
    required this.patientName,
    required this.dateTimeLabel,
    required this.reason,
    this.patientUserId,
  });
  final String id;
  final String patientName;
  final String dateTimeLabel;
  final String reason;
  final String? patientUserId;
}

class _ConfirmedAppointment {
  const _ConfirmedAppointment({
    required this.id,
    required this.patientName,
    required this.dateTimeLabel,
    required this.reason,
    this.patientUserId,
  });
  final String id;
  final String patientName;
  final String dateTimeLabel;
  final String reason;
  final String? patientUserId;
}

DateTime? _apptCreatedAt(Map<String, dynamic> m) {
  final c = m['createdAt'];
  if (c is Timestamp) return c.toDate();
  if (c is String) return DateTime.tryParse(c);
  return null;
}

bool _doctorApptShowOnHomePreview(Map<String, dynamic> m) {
  final s = (m['status'] ?? 'confirmed').toString().toLowerCase();
  return s != 'declined' && s != 'cancelled' && s != 'completed';
}

DateTime? _appointmentFirstSortTime(Map<String, dynamic> m) {
  final c = _apptCreatedAt(m);
  if (c != null) return c;
  final ds = (m['date'] ?? '').toString().trim();
  if (ds.isEmpty) return null;
  return DateTime.tryParse('${ds}T12:00:00');
}

int? _patientAgeYearsFromDetails(Map<String, dynamic>? data) {
  if (data == null) return null;
  final day = (data['dob_day'] as num?)?.toInt() ?? (data['age_day'] as num?)?.toInt();
  final month = (data['dob_month'] as num?)?.toInt() ?? (data['age_month'] as num?)?.toInt();
  final year = (data['dob_year'] as num?)?.toInt() ?? (data['age_year'] as num?)?.toInt();
  if (day == null || month == null || year == null) return null;
  try {
    final dob = DateTime(year, month, day);
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
    if (age > 0 && age < 120) return age;
  } catch (_) {}
  return null;
}

int? _ageGroupIndexForAge(int age) {
  if (age <= 30) return 0;
  if (age <= 50) return 1;
  if (age <= 65) return 2;
  return 3;
}

/// Builds age-group chart data from unique patients on this doctor's appointments (Firestore DOB).
Future<List<_DoctorAge>> _doctorAgeGroupsFromAppointmentDocs(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) async {
  const buckets = <(String label, Color color)>[
    ('Young Adult (18–30)', Color(0xFFF89A4C)),
    ('Adult (31–50)', Color(0xFF5D5FEF)),
    ('Mature (51–65)', Color(0xFF4CAF50)),
    ('Senior (65+)', Color(0xFF90CAF9)),
  ];

  final uids = <String>{};
  for (final d in docs) {
    final uid = (d.data()['userId'] ?? '').toString().trim();
    if (uid.isNotEmpty) uids.add(uid);
  }

  final counts = List<int>.filled(buckets.length, 0);
  if (uids.isEmpty || !FirebaseService.isInitialized) {
    return List.generate(buckets.length, (i) => _DoctorAge(buckets[i].$1, 0, 0, buckets[i].$2));
  }

  var patientsWithAge = 0;
  for (final uid in uids) {
    try {
      final snap = await FirebaseService.getPatientDetails(uid);
      final age = _patientAgeYearsFromDetails(snap?.data());
      final idx = age != null ? _ageGroupIndexForAge(age) : null;
      if (idx == null) continue;
      counts[idx]++;
      patientsWithAge++;
    } catch (_) {}
  }

  return List.generate(buckets.length, (i) {
    final c = counts[i];
    final pct = patientsWithAge > 0 ? ((c * 100) / patientsWithAge).round() : 0;
    return _DoctorAge(buckets[i].$1, c, pct, buckets[i].$2);
  });
}

List<_DoctorStat> _doctorDashboardStatsFromAppointmentDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  const window = Duration(days: 90);
  final cutoff = DateTime.now().subtract(window);
  final uidToFirst = <String, DateTime>{};
  for (final d in docs) {
    final m = d.data();
    final uid = (m['userId'] ?? '').toString().trim();
    if (uid.isEmpty) continue;
    final t = _appointmentFirstSortTime(m) ?? DateTime(2000);
    final prev = uidToFirst[uid];
    if (prev == null || t.isBefore(prev)) uidToFirst[uid] = t;
  }
  var newP = 0;
  var oldP = 0;
  for (final first in uidToFirst.values) {
    if (first.isAfter(cutoff)) {
      newP++;
    } else {
      oldP++;
    }
  }
  final totalPatients = uidToFirst.length;
  final appointments = docs.length;
  return [
    _DoctorStat('Total Patients', '$totalPatients', '', true),
    _DoctorStat('New Patients', '$newP', '', true),
    _DoctorStat('Old Patients', '$oldP', '', true),
    _DoctorStat('Appointments', '$appointments', '', true),
  ];
}

List<(String, int)> _weekAppointmentTrendFromDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final counts = List<int>.filled(7, 0);
  for (final d in docs) {
    final c = _apptCreatedAt(d.data());
    if (c == null) continue;
    final idx = c.weekday - 1;
    if (idx >= 0 && idx < 7) counts[idx]++;
  }
  return List.generate(7, (i) => (labels[i], counts[i]));
}

String _capitalizeStatusLabel(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return 'Confirmed';
  return s[0].toUpperCase() + (s.length > 1 ? s.substring(1) : '');
}

/// Dashboard strip: pending + confirmed (excludes declined/cancelled/completed).
List<(String, String, String, String, String?)> _doctorHomePreviewRowsFromDocs(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final filtered = docs.where((d) => _doctorApptShowOnHomePreview(d.data())).toList();
  filtered.sort((a, b) {
    final ta = _appointmentFirstSortTime(a.data());
    final tb = _appointmentFirstSortTime(b.data());
    if (ta != null && tb != null) {
      final c = ta.compareTo(tb);
      if (c != 0) return c;
    }
    final ad = (a.data()['date'] ?? '').toString();
    final bd = (b.data()['date'] ?? '').toString();
    final c = ad.compareTo(bd);
    if (c != 0) return c;
    return (a.data()['timeSlot'] ?? '').toString().compareTo((b.data()['timeSlot'] ?? '').toString());
  });
  return filtered.take(8).map((d) {
    final m = d.data();
    final rawName = (m['patientName'] ?? m['patient_name'] ?? '').toString().trim();
    final uid = (m['userId'] ?? '').toString().trim();
    final patient = rawName.isNotEmpty ? rawName : (uid.isNotEmpty ? uid : 'Patient');
    final date = (m['date'] ?? '').toString();
    final time = (m['timeSlot'] ?? '').toString();
    final reason = (m['consultationNotes'] ?? m['city'] ?? 'Consultation').toString();
    final status = _capitalizeStatusLabel((m['status'] ?? 'confirmed').toString());
    return (patient, [date, time].where((e) => e.isNotEmpty).join(' · '), reason, status, uid.isEmpty ? null : uid);
  }).toList();
}

/// Resolves display name from [patient_details] when appointment has no [patientName].
class _DoctorPatientTitle extends StatefulWidget {
  const _DoctorPatientTitle({
    required this.fallback,
    required this.userId,
    required this.style,
  });

  final String fallback;
  final String? userId;
  final TextStyle style;

  @override
  State<_DoctorPatientTitle> createState() => _DoctorPatientTitleState();
}

class _DoctorPatientTitleState extends State<_DoctorPatientTitle> {
  String? _resolved;

  @override
  void initState() {
    super.initState();
    final t = widget.fallback.trim();
    if (t.isNotEmpty && t != 'Patient') {
      _resolved = t;
      return;
    }
    final u = widget.userId?.trim();
    if (u == null || u.isEmpty) {
      _resolved = t.isEmpty ? 'Patient' : t;
      return;
    }
    FirebaseService.getPatientDetails(u).then((snap) {
      if (!mounted) return;
      var name = widget.fallback.trim();
      final data = snap?.data();
      if (data != null) {
        final n = (data['fullName'] ?? data['name'] ?? data['displayName'] ?? '').toString().trim();
        if (n.isNotEmpty) name = n;
      }
      if (name.isEmpty) name = 'Patient';
      setState(() => _resolved = name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = _resolved;
    if (v != null) {
      return Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: widget.style);
    }
    return Text(
      widget.fallback.trim().isEmpty ? '…' : widget.fallback,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: widget.style,
    );
  }
}

/// Loads this doctor's Firestore appointments; accept/decline updates status and notifies the patient.
class DoctorAppointmentsFirestore extends StatefulWidget {
  const DoctorAppointmentsFirestore({super.key, required this.doctorId});

  final String doctorId;

  @override
  State<DoctorAppointmentsFirestore> createState() => _DoctorAppointmentsFirestoreState();
}

class _DoctorAppointmentsFirestoreState extends State<DoctorAppointmentsFirestore> {
  final Set<String> _busy = {};

  Future<void> _accept(BuildContext context, String docId, Map<String, dynamic> data) async {
    final messenger = ScaffoldMessenger.of(context);
    if (_busy.contains(docId)) return;
    setState(() => _busy.add(docId));
    try {
      final mDoctorId = (data['doctorId'] ?? data['doctorID'] ?? '').toString();
      if (mDoctorId != widget.doctorId) {
        messenger.showSnackBar(const SnackBar(content: Text('This booking is not assigned to you.')));
        return;
      }
      final ok = await FirebaseService.updateAppointment(docId, {'status': 'confirmed'});
      if (!ok) {
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(content: Text('Could not confirm. Check connection and try again.')));
        return;
      }
      final patientUid = (data['userId'] ?? '').toString();
      if (patientUid.isNotEmpty) {
        ChatService.instance.ensureConversationAfterAccept(
          appointmentId: docId,
          patientId: patientUid,
          doctorId: widget.doctorId,
          patientName: (data['patientName'] ?? 'Patient').toString(),
          doctorName: (data['doctorName'] ?? 'Your doctor').toString(),
          date: data['date']?.toString(),
          timeSlot: (data['timeSlot'] ?? data['time'])?.toString(),
        );
      }
      if (patientUid.isNotEmpty) {
        final dn = (data['doctorName'] ?? 'Your doctor').toString();
        final dt = [data['date'], data['timeSlot']].where((e) => e != null && '$e'.trim().isNotEmpty).join(' ').trim();
        await FirebaseService.addPatientNotification(
          userId: patientUid,
          title: 'Appointment confirmed',
          body: dt.isEmpty ? '$dn confirmed your appointment request.' : '$dn confirmed your appointment for $dt.',
          type: 'appointment',
          extra: {'appointmentId': docId, 'event': 'confirmed'},
        );
      }
      if (!mounted) return;
      final name = (data['patientName'] ?? 'Patient').toString();
      messenger.showSnackBar(SnackBar(content: Text('Confirmed with $name')));
    } finally {
      if (mounted) setState(() => _busy.remove(docId));
    }
  }

  Future<void> _decline(BuildContext context, String docId, Map<String, dynamic> data) async {
    final messenger = ScaffoldMessenger.of(context);
    if (_busy.contains(docId)) return;
    setState(() => _busy.add(docId));
    try {
      final mDoctorId = (data['doctorId'] ?? data['doctorID'] ?? '').toString();
      if (mDoctorId != widget.doctorId) {
        messenger.showSnackBar(const SnackBar(content: Text('This booking is not assigned to you.')));
        return;
      }
      final ok = await FirebaseService.updateAppointment(docId, {'status': 'declined'});
      if (!ok) {
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(content: Text('Could not update. Try again.')));
        return;
      }
      final patientUid = (data['userId'] ?? '').toString();
      if (patientUid.isNotEmpty) {
        final dn = (data['doctorName'] ?? 'The clinic').toString();
        final dt = [data['date'], data['timeSlot']].where((e) => e != null && '$e'.trim().isNotEmpty).join(' ').trim();
        await FirebaseService.addPatientNotification(
          userId: patientUid,
          title: 'Appointment update',
          body: dt.isEmpty
              ? '$dn is not available for that slot. Please choose another time.'
              : '$dn could not accept your request for $dt. Please choose another time.',
          type: 'appointment',
          extra: {'appointmentId': docId, 'event': 'declined'},
        );
      }
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Request declined')));
    } finally {
      if (mounted) setState(() => _busy.remove(docId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: FirebaseService.getAppointmentsForDoctor(widget.doctorId),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load appointments.\n${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
        }
        final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(snap.data ?? const []);
        final pending = <_PendingRequest>[];
        final confirmed = <_ConfirmedAppointment>[];
        for (final d in docs) {
          final m = d.data();
          final stRaw = m['status'];
          final st = stRaw == null ? '' : stRaw.toString().trim().toLowerCase();
          final rawName = (m['patientName'] ?? m['patient_name'] ?? '').toString().trim();
          final patientUid = (m['userId'] ?? '').toString().trim();
          final patientName = rawName.isNotEmpty ? rawName : (patientUid.isNotEmpty ? patientUid : 'Patient');
          final date = (m['date'] ?? '').toString();
          final time = (m['timeSlot'] ?? '').toString();
          final dateTimeLabel = [date, time].where((e) => e.isNotEmpty).join(' · ');
          final reason = (m['consultationNotes'] ?? m['city'] ?? 'Consultation').toString();
          if (st == 'declined' || st == 'cancelled' || st == 'completed') {
            continue;
          }
          if (st == 'confirmed' || st == 'accepted') {
            confirmed.add(
              _ConfirmedAppointment(
                id: d.id,
                patientName: patientName,
                patientUserId: patientUid.isEmpty ? null : patientUid,
                dateTimeLabel: dateTimeLabel,
                reason: reason,
              ),
            );
          } else {
            // pending, requested, empty, unknown — show under Requests so new bookings are never hidden
            pending.add(
              _PendingRequest(
                id: d.id,
                patientName: patientName,
                patientUserId: patientUid.isEmpty ? null : patientUid,
                dateTimeLabel: dateTimeLabel,
                reason: reason,
              ),
            );
          }
        }

        pending.sort((a, b) {
          Map<String, dynamic>? ma;
          Map<String, dynamic>? mb;
          for (final e in docs) {
            if (e.id == a.id) ma = e.data();
            if (e.id == b.id) mb = e.data();
          }
          final ta = ma != null ? _apptCreatedAt(ma) : null;
          final tb = mb != null ? _apptCreatedAt(mb) : null;
          if (ta != null && tb != null) return tb.compareTo(ta);
          return b.id.compareTo(a.id);
        });
        confirmed.sort((a, b) => a.dateTimeLabel.compareTo(b.dateTimeLabel));

        return _DoctorAppointmentsPage(
          pending: pending,
          confirmed: confirmed,
          onAccept: (id) {
            for (final e in docs) {
              if (e.id == id) {
                _accept(context, id, e.data());
                return;
              }
            }
          },
          onDecline: (id) {
            for (final e in docs) {
              if (e.id == id) {
                _decline(context, id, e.data());
                return;
              }
            }
          },
        );
      },
    );
  }
}

class DoctorDashboardScreen extends StatefulWidget {
  const DoctorDashboardScreen({super.key, this.section = 'dashboard'});

  final String section;

  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends State<DoctorDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDesktop = MediaQuery.sizeOf(context).width >= 1000;
    final active =
        widget.section == 'appointments' || widget.section == 'patients' ? widget.section : 'dashboard';
    final routePath = GoRouterState.of(context).uri.path;
    final doctorId = auth.userId;

    final Widget bodyBelowTopBar;
    if (active == 'appointments') {
      bodyBelowTopBar = Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        child: doctorId == null || doctorId.isEmpty
            ? Center(child: Text(context.t('sign_in_doctor_appointments'), style: TextStyle(color: context.sh.textPrimary)))
            : DoctorAppointmentsFirestore(doctorId: doctorId),
      );
    } else if (active == 'patients') {
      bodyBelowTopBar = Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        child: doctorId == null || doctorId.isEmpty
            ? Center(child: Text(context.t('sign_in_doctor_appointments'), style: TextStyle(color: context.sh.textPrimary)))
            : _DoctorPatientsFromFirestore(doctorId: doctorId),
      );
    } else if (doctorId == null || doctorId.isEmpty) {
      bodyBelowTopBar = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
        child: _DoctorDashboardMain(
          stats: _doctorDashboardStatsFromAppointmentDocs(const []),
          ageGroups: const [],
          upcoming: const [],
          trend: _weekAppointmentTrendFromDocs(const []),
        ),
      );
    } else {
      bodyBelowTopBar = StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: FirebaseService.getAppointmentsForDoctor(doctorId),
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text('Could not load appointments: ${snap.error}')),
            );
          }
          final docs = snap.data ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final upcoming = _doctorHomePreviewRowsFromDocs(docs);
          final docKey = docs.map((d) => d.id).join(',');
          return FutureBuilder<List<_DoctorAge>>(
            key: ValueKey(docKey),
            future: _doctorAgeGroupsFromAppointmentDocs(docs),
            builder: (context, ageSnap) {
              final ageGroups = ageSnap.data ?? const <_DoctorAge>[];
              final stats = _doctorDashboardStatsFromAppointmentDocs(docs);
              final trend = _weekAppointmentTrendFromDocs(docs);
              if (ageSnap.connectionState == ConnectionState.waiting && !ageSnap.hasData) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: CircularProgressIndicator(color: context.sh.textPrimary),
                  ),
                );
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
                child: _DoctorDashboardMain(
                  stats: stats,
                  ageGroups: ageGroups,
                  upcoming: upcoming,
                  trend: trend,
                ),
              );
            },
          );
        },
      );
    }

    final scrollBody = Container(
      color: context.sh.scaffold,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DoctorTopBar(
              userName: auth.userName ?? 'Doctor',
              showMenuButton: !isDesktop,
            ),
            Expanded(child: bodyBelowTopBar),
          ],
        ),
      ),
    );

    if (!isDesktop) {
      return Scaffold(
        drawer: _DoctorSidebar(current: active),
        body: Stack(
          children: [
            Positioned.fill(child: scrollBody),
            if (!kIsWeb)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _DoctorFloatingBottomNav(currentPath: routePath),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Row(
              children: [
                _DoctorSidebar(current: active),
                Expanded(child: scrollBody),
              ],
            ),
          ),
          if (!kIsWeb)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _DoctorFloatingBottomNav(currentPath: routePath),
            ),
        ],
      ),
    );
  }
}

class _DoctorTopBar extends StatelessWidget {
  const _DoctorTopBar({
    required this.userName,
    this.showMenuButton = false,
  });

  final String userName;
  final bool showMenuButton;

  static Widget _brandRow(BuildContext context) {
    final sh = context.sh;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset('assets/logo.png', width: 28, height: 28, fit: BoxFit.cover),
        ),
        const SizedBox(width: 8),
        Text(
          context.t('app_name'),
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: sh.textPrimary),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    return Container(
      height: kToolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: sh.appBar,
        border: Border(bottom: BorderSide(color: sh.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showMenuButton)
            IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: Icon(Icons.menu_rounded, color: context.sh.textPrimary),
            ),
          if (showMenuButton) const SizedBox(width: 2),
          Expanded(
            child: Center(child: _brandRow(context)),
          ),
          PopupMenuButton<String>(
            tooltip: 'Profile',
            color: context.sh.card,
            itemBuilder: (ctx) => [
              PopupMenuItem<String>(
                value: 'settings',
                child: Text(ctx.t('settings'), style: TextStyle(color: ctx.sh.textPrimary)),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                child: Text(ctx.t('logout'), style: TextStyle(color: ctx.sh.textPrimary)),
              ),
            ],
            onSelected: (value) async {
              if (value == 'settings') {
                if (context.mounted) context.push('/settings');
                return;
              }
              if (value == 'logout') {
                await context.read<AuthProvider>().signOut();
                if (context.mounted) context.go('/role');
              }
            },
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.black,
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : 'D',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoctorFloatingBottomNav extends StatelessWidget {
  const _DoctorFloatingBottomNav({required this.currentPath});

  final String currentPath;

  bool _selected(String route) {
    if (route == '/chat-list') {
      return currentPath.startsWith('/chat');
    }
    if (route == '/doctor-profile') {
      return currentPath == '/doctor-profile' || currentPath.startsWith('/doctor-profile/');
    }
    if (route == '/doctor-dashboard') {
      return currentPath == '/doctor-dashboard';
    }
    return currentPath == route || currentPath.startsWith('$route/');
  }

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        height: 74,
        decoration: BoxDecoration(
          color: sh.navBar,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _DoctorNavItem(
              icon: Icons.home_rounded,
              label: context.t('nav_home'),
              selected: _selected('/doctor-dashboard'),
              onTap: () => context.go('/doctor-dashboard'),
              sh: sh,
            ),
            _DoctorNavItem(
              icon: Icons.calendar_month_outlined,
              label: context.t('nav_appointments'),
              selected: _selected('/doctor-appointments'),
              onTap: () => context.go('/doctor-appointments'),
              sh: sh,
            ),
            _DoctorNavItem(
              icon: Icons.people_outline,
              label: context.t('nav_patients'),
              selected: _selected('/doctor-patients'),
              onTap: () => context.go('/doctor-patients'),
              sh: sh,
            ),
            _DoctorNavItem(
              icon: Icons.person_outline,
              label: context.t('profile'),
              selected: _selected('/doctor-profile'),
              onTap: () => context.go('/doctor-profile'),
              sh: sh,
            ),
            if (!kIsWeb)
              _DoctorNavItem(
                icon: Icons.chat_outlined,
                label: context.t('nav_chat'),
                selected: _selected('/chat-list'),
                onTap: () => context.go('/chat-list'),
                sh: sh,
              ),
          ],
        ),
      ),
    );
  }
}

class _DoctorNavItem extends StatelessWidget {
  const _DoctorNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.sh,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final SafeHairColors sh;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? sh.selectedNavBg : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 22,
                color: selected ? sh.selectedNavFg : sh.unselectedNavFg,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? sh.textPrimary : sh.unselectedNavFg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoctorSidebar extends StatelessWidget {
  const _DoctorSidebar({required this.current});

  final String current;
  static const _width = 260.0;

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    return SizedBox(
      width: _width,
      child: Container(
        color: sh.card,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(0xFFEFEFEF),
                      child: Image(image: AssetImage('assets/logo.png')),
                    ),
                    const SizedBox(width: 10),
                    Text(context.t('app_name'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: sh.textPrimary)),
                  ],
                ),
              ),
              _SidebarItem(
                icon: Icons.dashboard_outlined,
                label: context.t('nav_dashboard'),
                selected: current == 'dashboard',
                onTap: () => context.go('/doctor-dashboard'),
                sh: sh,
              ),
              _SidebarItem(
                icon: Icons.calendar_month_outlined,
                label: context.t('nav_appointments'),
                selected: current == 'appointments',
                onTap: () => context.go('/doctor-appointments'),
                sh: sh,
              ),
              _SidebarItem(
                icon: Icons.people_outline,
                label: context.t('nav_patients'),
                selected: current == 'patients',
                onTap: () => context.go('/doctor-patients'),
                sh: sh,
              ),
              _SidebarItem(
                icon: Icons.person_outline,
                label: context.t('nav_my_profile'),
                selected: GoRouterState.of(context).matchedLocation.startsWith('/doctor-profile'),
                onTap: () => context.go('/doctor-profile'),
                sh: sh,
              ),
              _SidebarItem(
                icon: Icons.chat_bubble_outline,
                label: context.t('nav_my_chats'),
                selected: GoRouterState.of(context).matchedLocation.startsWith('/chat'),
                onTap: () => context.go('/chat-list'),
                sh: sh,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.sh,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final SafeHairColors sh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: selected ? sh.sidebarSelectedBg : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: sh.icon),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: sh.textPrimary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DoctorDashboardMain extends StatelessWidget {
  const _DoctorDashboardMain({
    required this.stats,
    required this.ageGroups,
    required this.upcoming,
    required this.trend,
  });

  final List<_DoctorStat> stats;
  final List<_DoctorAge> ageGroups;
  final List<(String, String, String, String, String?)> upcoming;
  final List<(String, int)> trend;

  @override
  Widget build(BuildContext context) {
    final statGrid = Column(
      children: [
        Row(
          children: [
            Expanded(child: _StatCard(stat: stats[0])),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(stat: stats[1])),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _StatCard(stat: stats[2])),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(stat: stats[3])),
          ],
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        statGrid,
        const SizedBox(height: 16),
        _AgePieCard(ageGroups: ageGroups),
        const SizedBox(height: 16),
        _UpcomingAppointmentsCard(items: upcoming),
        const SizedBox(height: 16),
        _AppointmentTrendCard(points: trend),
      ],
    );
  }
}

class _UpcomingAppointmentsCard extends StatelessWidget {
  const _UpcomingAppointmentsCard({required this.items});
  final List<(String, String, String, String, String?)> items;

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sh.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('upcoming_appointments'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: sh.textPrimary)),
          const SizedBox(height: 12),
          SizedBox(
            height: 102,
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'No appointments yet',
                      style: TextStyle(color: sh.textSecondary, fontWeight: FontWeight.w600),
                    ),
                  )
                : ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                return Container(
                  width: 220,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: sh.sidebarSelectedBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sh.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _DoctorPatientTitle(
                              fallback: item.$1,
                              userId: item.$5,
                              style: TextStyle(fontWeight: FontWeight.w700, color: sh.textPrimary),
                            ),
                          ),
                          if (doctorAppointmentAllowsClinicalView(item.$4)) ...[
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 60,
                              height: 30,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  backgroundColor: sh.selectedNavBg,
                                  foregroundColor: sh.selectedNavFg,
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(60, 30),
                                  fixedSize: const Size(60, 30),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () {
                                  openDoctorPatientClinical(
                                    context,
                                    patientUserId: item.$5,
                                    patientName: item.$1,
                                    appointmentDateTime: item.$2,
                                    reason: item.$3,
                                    canViewReport: true,
                                  );
                                },
                                child: const Text('View', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 16, color: sh.textSecondary),
                          const SizedBox(width: 6),
                          Expanded(child: Text(item.$2, style: TextStyle(fontSize: 12, color: sh.textSecondary))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.medical_information_outlined, size: 16, color: sh.textSecondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: sh.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      if (item.$4.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: item.$4.toLowerCase() == 'pending' ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              item.$4,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: item.$4.toLowerCase() == 'pending' ? const Color(0xFFE65100) : const Color(0xFF2E7D32),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentTrendCard extends StatelessWidget {
  const _AppointmentTrendCard({required this.points});
  final List<(String, int)> points;

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    if (points.isEmpty) return const SizedBox.shrink();
    final spots = [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].$2.toDouble())];
    var minY = points.map((e) => e.$2).reduce(math.min).toDouble();
    var maxY = points.map((e) => e.$2).reduce(math.max).toDouble();
    if (maxY == minY) {
      minY -= 2;
      maxY += 2;
    }
    minY = math.max(0, minY - 4);
    maxY += 6;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sh.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('appointment_trends'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: sh.textPrimary)),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (points.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 5,
                  getDrawingHorizontalLine: (_) => FlLine(color: sh.border),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(fontSize: 10, color: sh.textSecondary),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.round();
                        if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(points[idx].$1, style: TextStyle(fontSize: 11, color: sh.textSecondary)),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    color: const Color(0xFF5D5FEF),
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    spots: spots,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});
  final _DoctorStat stat;

  @override
  Widget build(BuildContext context) {
    final trendColor = stat.positive ? const Color(0xFF2EAE56) : const Color(0xFFE05A63);
    IconData iconFor(String title) {
      if (title == 'Total Patients') return Icons.people_outline;
      if (title == 'New Patients') return Icons.person_add_alt_1_outlined;
      if (title == 'Old Patients') return Icons.person_outline;
      return Icons.calendar_today_outlined;
    }

    Color iconTint(String title) {
      if (title == 'Total Patients') return const Color(0xFF2563EB);
      if (title == 'New Patients') return const Color(0xFF7C3AED);
      if (title == 'Old Patients') return const Color(0xFF16A34A);
      return const Color(0xFFEA580C);
    }

    Color iconBg(String title) {
      if (title == 'Total Patients') return const Color(0xFFE8F1FE);
      if (title == 'New Patients') return const Color(0xFFF3E8FF);
      if (title == 'Old Patients') return const Color(0xFFE8F8EE);
      return const Color(0xFFFFF3E8);
    }

    final c = iconTint(stat.title);
    final bg = iconBg(stat.title);
    final sh = context.sh;
    final titleKey = AppTranslations.statTitleKey(stat.title);
    final localizedTitle = titleKey.startsWith('stat_') ? context.t(titleKey) : stat.title;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sh.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(iconFor(stat.title), color: c, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.topRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      stat.value,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: sh.textPrimary),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            localizedTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: sh.textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (stat.change.trim().isNotEmpty) ...[
                Icon(stat.positive ? Icons.trending_up : Icons.trending_down, color: trendColor, size: 16),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    stat.change,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: trendColor, fontWeight: FontWeight.w700, fontSize: 11),
                  ),
                ),
              ] else
                Flexible(
                  child: Text(
                    context.t('live_from_bookings'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: sh.textSecondary, fontWeight: FontWeight.w600, fontSize: 11),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgePieCard extends StatefulWidget {
  const _AgePieCard({required this.ageGroups});
  final List<_DoctorAge> ageGroups;

  @override
  State<_AgePieCard> createState() => _AgePieCardState();
}

class _AgePieCardState extends State<_AgePieCard> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    final ageGroups = widget.ageGroups;
    final totalPatients = ageGroups.fold<int>(0, (s, g) => s + g.count);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sh.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('patient_age_groups'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: sh.textPrimary)),
          const SizedBox(height: 12),
          if (totalPatients == 0)
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  'No patient age data yet. Ages appear when patients complete their profile date of birth.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: sh.textSecondary, fontWeight: FontWeight.w500, height: 1.35),
                ),
              ),
            )
          else
          SizedBox(
            height: 260,
            child: PieChart(
              PieChartData(
                centerSpaceRadius: 52,
                sectionsSpace: 2,
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                    if (!event.isInterestedForInteractions) {
                      setState(() => _touchedIndex = null);
                      return;
                    }
                    final touched = pieTouchResponse?.touchedSection;
                    if (touched == null) {
                      setState(() => _touchedIndex = null);
                      return;
                    }
                    setState(() => _touchedIndex = touched.touchedSectionIndex);
                  },
                ),
                sections: List.generate(
                  ageGroups.length,
                  (i) {
                    final g = ageGroups[i];
                    final touched = _touchedIndex == i;
                    return PieChartSectionData(
                      value: g.count > 0 ? g.count.toDouble() : 0.001,
                      color: g.color,
                      radius: 62,
                      title: touched ? '${g.title}\n${g.count} (${g.percent}%)' : '${g.percent}%',
                      titleStyle: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: touched ? 9 : 10,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          if (totalPatients > 0) ...[
            const SizedBox(height: 8),
            ...ageGroups.map(
              (g) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: g.color, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${g.title}: ${g.count} (${g.percent}%)',
                        style: TextStyle(fontWeight: FontWeight.w600, color: sh.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DoctorAppointmentsPage extends StatelessWidget {
  const _DoctorAppointmentsPage({
    required this.pending,
    required this.confirmed,
    required this.onAccept,
    required this.onDecline,
  });

  final List<_PendingRequest> pending;
  final List<_ConfirmedAppointment> confirmed;
  final void Function(String id) onAccept;
  final void Function(String id) onDecline;

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    return DefaultTabController(
      length: 2,
      initialIndex: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: sh.card,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: sh.border),
            ),
            child: TabBar(
              indicator: const BoxDecoration(),
              labelColor: sh.textPrimary,
              unselectedLabelColor: sh.textSecondary,
              dividerColor: Colors.transparent,
              dividerHeight: 0,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              tabs: const [
                Tab(text: 'Requests'),
                Tab(text: 'Upcoming'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              children: [
                _AppointmentRequestsList(pending: pending, onAccept: onAccept, onDecline: onDecline),
                _AppointmentUpcomingList(confirmed: confirmed),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentRequestsList extends StatelessWidget {
  const _AppointmentRequestsList({
    required this.pending,
    required this.onAccept,
    required this.onDecline,
  });

  final List<_PendingRequest> pending;
  final void Function(String id) onAccept;
  final void Function(String id) onDecline;

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    if (pending.isEmpty) {
      return Center(
        child: Text(
          'No pending requests',
          style: TextStyle(color: sh.textSecondary, fontWeight: FontWeight.w600, fontSize: 15),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: pending.length,
      itemBuilder: (context, index) {
        final r = pending[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: sh.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sh.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DoctorPatientTitle(
                        fallback: r.patientName,
                        userId: r.patientUserId,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: sh.textPrimary),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.access_time, size: 18, color: sh.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              r.dateTimeLabel,
                              style: TextStyle(fontSize: 13, color: sh.textSecondary, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.medical_information_outlined, size: 18, color: sh.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              r.reason,
                              style: TextStyle(fontSize: 13, color: sh.textSecondary, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => onAccept(r.id),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: sh.sidebarSelectedBg,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.green.shade300, width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.check, color: Colors.green.shade300, size: 22),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => onDecline(r.id),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: sh.sidebarSelectedBg,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.red.shade300, width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.close, color: Colors.red.shade300, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AppointmentUpcomingList extends StatelessWidget {
  const _AppointmentUpcomingList({required this.confirmed});

  final List<_ConfirmedAppointment> confirmed;

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    if (confirmed.isEmpty) {
      return Center(
        child: Text(
          'No upcoming appointments',
          style: TextStyle(color: sh.textSecondary, fontWeight: FontWeight.w600, fontSize: 15),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: confirmed.length,
      itemBuilder: (context, index) {
        final a = confirmed[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: sh.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sh.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _DoctorPatientTitle(
                        fallback: a.patientName,
                        userId: a.patientUserId,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: sh.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 60,
                      height: 30,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: sh.selectedNavBg,
                          foregroundColor: sh.selectedNavFg,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(60, 30),
                          fixedSize: const Size(60, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          openDoctorPatientClinical(
                            context,
                            patientUserId: a.patientUserId,
                            patientName: a.patientName,
                            appointmentDateTime: a.dateTimeLabel,
                            reason: a.reason,
                            canViewReport: true,
                          );
                        },
                        child: const Text('View', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.access_time, size: 18, color: sh.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        a.dateTimeLabel,
                        style: TextStyle(fontSize: 13, color: sh.textSecondary, height: 1.3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.medical_information_outlined, size: 18, color: sh.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        a.reason,
                        style: TextStyle(fontSize: 13, color: sh.textSecondary, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DoctorPatientsFromFirestore extends StatefulWidget {
  const _DoctorPatientsFromFirestore({required this.doctorId});

  final String doctorId;

  @override
  State<_DoctorPatientsFromFirestore> createState() => _DoctorPatientsFromFirestoreState();
}

class _DoctorPatientsFromFirestoreState extends State<_DoctorPatientsFromFirestore> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: FirebaseService.getAppointmentsForDoctor(widget.doctorId),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              'Could not load patients.\n${snap.error}',
              textAlign: TextAlign.center,
              style: TextStyle(color: sh.textSecondary, fontWeight: FontWeight.w600),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Center(child: CircularProgressIndicator(color: sh.textPrimary));
        }
        final all = practicePatientsFromAppointmentDocs(snap.data ?? const []);
        final q = _search.text.trim().toLowerCase();
        final filtered = q.isEmpty
            ? all
            : all.where((p) => p.displayName.toLowerCase().contains(q)).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: sh.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search by patient name...',
                hintStyle: TextStyle(color: sh.textSecondary),
                prefixIcon: Icon(Icons.search, color: sh.textSecondary),
                filled: true,
                fillColor: sh.card,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: sh.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: sh.border)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: sh.textPrimary),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        all.isEmpty
                            ? 'Patients appear here after you confirm their appointments.'
                            : 'No patients match your search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: sh.textSecondary, fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final p = filtered[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: sh.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: sh.border),
                            boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: sh.sidebarSelectedBg,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: sh.border),
                                ),
                                child: Text(
                                  p.displayName.isNotEmpty ? p.displayName[0].toUpperCase() : '?',
                                  style: TextStyle(color: sh.textPrimary, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _DoctorPatientTitle(
                                      fallback: p.displayName,
                                      userId: p.userId,
                                      style: TextStyle(fontWeight: FontWeight.w700, color: sh.textPrimary),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Last visit: ${p.lastVisit} • ${p.consultations} consultation(s)',
                                      style: TextStyle(color: sh.textSecondary, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 88,
                                height: 30,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    backgroundColor: sh.sidebarSelectedBg,
                                    foregroundColor: sh.textPrimary,
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(88, 30),
                                    fixedSize: const Size(88, 30),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    side: BorderSide(color: sh.border),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () {
                                    openDoctorPatientClinical(
                                      context,
                                      patientUserId: p.userId,
                                      patientName: p.displayName,
                                      appointmentDateTime: p.lastVisit,
                                      reason: '${p.consultations} confirmed consultation(s)',
                                      canViewReport: true,
                                    );
                                  },
                                  child: const Text('View Profile', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _DoctorStat {
  const _DoctorStat(this.title, this.value, this.change, this.positive);
  final String title;
  final String value;
  final String change;
  final bool positive;
}

class _DoctorAge {
  const _DoctorAge(this.title, this.count, this.percent, this.color);
  final String title;
  final int count;
  final int percent;
  final Color color;
}
