import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/safe_hair_colors.dart';
import '../services/firebase_service.dart';
import 'scalp_report_detail_screen.dart';

/// Clinical view for doctors: demographics + AI summary only (no phone, address, email).
class DoctorPatientClinicalPage extends StatefulWidget {
  const DoctorPatientClinicalPage({
    super.key,
    required this.patientUserId,
    required this.patientNameFallback,
    required this.appointmentDateTime,
    required this.reason,
    required this.canViewReport,
  });

  final String patientUserId;
  final String patientNameFallback;
  final String appointmentDateTime;
  final String reason;
  final bool canViewReport;

  @override
  State<DoctorPatientClinicalPage> createState() => _DoctorPatientClinicalPageState();
}

class _DoctorPatientClinicalPageState extends State<DoctorPatientClinicalPage> {
  bool _loading = true;
  String? _error;
  String _displayName = '';
  String? _ageLabel;
  String? _gender;
  String _aiSummary = '';
  String? _latestReportId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int? _ageYearsFromDetails(Map<String, dynamic>? data) {
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

  String _summaryFromMaps(Map<String, dynamic>? patient, Map<String, dynamic>? report) {
    final d = report ?? patient;
    if (d == null) {
      return 'No scalp analysis on file yet. The patient can run a scan from My Scans.';
    }
    final overall = (d['overallScore'] as num?)?.round() ??
        (d['averageScore'] as num?)?.round() ??
        (patient?['hairStrengthPct'] != null ? _avgFromPatient(patient!) : null);
    final strength = (d['strength'] as num?)?.round() ?? (patient?['hairStrengthPct'] as num?)?.round();
    final scalp = (d['scalpHealth'] as num?)?.round() ??
        (d['scalp'] as num?)?.round() ??
        (patient?['hairScalpHealthPct'] as num?)?.round();
    final damage = (d['hairDamage'] as num?)?.round() ??
        (d['damage'] as num?)?.round() ??
        (patient?['hairDamageLevelPct'] as num?)?.round();
    final fall = (d['hairFallRisk'] as num?)?.round() ?? (patient?['hairFallRiskPct'] as num?)?.round();
    final tip = patient?['hairLatestRoutineTip']?.toString().trim();
    final buf = StringBuffer();
    if (overall != null) buf.writeln('Overall score: $overall/100');
    if (strength != null || scalp != null) {
      buf.writeln(
        'Hair strength: ${strength ?? '—'} • Scalp health: ${scalp ?? '—'}',
      );
    }
    if (damage != null || fall != null) {
      buf.writeln('Damage level: ${damage ?? '—'} • Fall risk: ${fall ?? '—'}');
    }
    if (tip != null && tip.isNotEmpty) buf.writeln('Care tip: $tip');
    final text = buf.toString().trim();
    return text.isEmpty ? 'Scan data is limited. Open the full report when available.' : text;
  }

  int? _avgFromPatient(Map<String, dynamic> p) {
    final s = (p['hairStrengthPct'] as num?)?.toInt();
    final sc = (p['hairScalpHealthPct'] as num?)?.toInt();
    final d = (p['hairDamageLevelPct'] as num?)?.toInt();
    final f = (p['hairFallRiskPct'] as num?)?.toInt();
    if (s == null || sc == null || d == null || f == null) return null;
    return FirebaseService.hairHealthAverageScore(s, sc, d, f).round();
  }

  Future<void> _load() async {
    if (!FirebaseService.isInitialized) {
      setState(() {
        _loading = false;
        _error = 'Firebase is not available.';
      });
      return;
    }
    try {
      final patientSnap = await FirebaseService.getPatientDetails(widget.patientUserId);
      final patient = patientSnap?.data();
      final name = patient?['name']?.toString().trim();
      _displayName = (name != null && name.isNotEmpty) ? name : widget.patientNameFallback;
      final age = _ageYearsFromDetails(patient);
      _ageLabel = age != null ? '$age' : null;
      final g = patient?['gender']?.toString().trim();
      _gender = (g != null && g.isNotEmpty) ? g : null;

      Map<String, dynamic>? reportData;
      if (widget.canViewReport) {
        final latest = await FirebaseService.getLatestPatientReport(widget.patientUserId);
        if (latest != null) {
          _latestReportId = latest.$1;
          reportData = latest.$2;
        }
      }
      _aiSummary = widget.canViewReport
          ? _summaryFromMaps(patient, reportData)
          : 'Accept this appointment to view the patient\'s AI scalp analysis and full report.';
    } catch (e) {
      _error = 'Could not load patient details.';
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    return Scaffold(
      backgroundColor: sh.scaffold,
      appBar: AppBar(
        title: Text('Patient details', style: TextStyle(fontWeight: FontWeight.w700, color: sh.textPrimary)),
        backgroundColor: sh.appBar,
        foregroundColor: sh.textPrimary,
        elevation: 0,
        surfaceTintColor: sh.appBar,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: sh.textPrimary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: sh.textSecondary)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _sectionTitle(context, 'Patient'),
                    _infoRow(context, 'Name', _displayName),
                    if (_ageLabel != null) _infoRow(context, 'Age', _ageLabel!),
                    if (_gender != null) _infoRow(context, 'Gender', _gender!),
                    const SizedBox(height: 20),
                    _sectionTitle(context, 'AI scalp analysis (summary)'),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _aiSummary,
                        style: TextStyle(fontSize: 15, color: sh.textSecondary, height: 1.45),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle(context, 'Appointment'),
                    _infoRow(context, 'Date & time', widget.appointmentDateTime),
                    _infoRow(context, 'Reason', widget.reason),
                    if (!widget.canViewReport) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: sh.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: sh.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: sh.textSecondary, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Confirm the appointment request to unlock the full AI report.',
                                style: TextStyle(color: sh.textSecondary, fontSize: 14, height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (widget.canViewReport && _latestReportId != null) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: sh.selectedNavBg,
                            foregroundColor: sh.selectedNavFg,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (ctx) => ScalpReportDetailScreen(
                                  reportId: _latestReportId!,
                                  patientUserId: widget.patientUserId,
                                ),
                              ),
                            );
                          },
                          child: const Text('View Full AI Report', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }

  Widget _sectionTitle(BuildContext context, String t) {
    final sh = context.sh;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: sh.textPrimary)),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final sh = context.sh;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 15, color: sh.textSecondary, height: 1.35),
          children: [
            TextSpan(text: '$label: ', style: TextStyle(fontWeight: FontWeight.w600, color: sh.textPrimary)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

/// Opens clinical patient page when [patientUserId] is set.
void openDoctorPatientClinical(
  BuildContext context, {
  required String? patientUserId,
  required String patientName,
  required String appointmentDateTime,
  required String reason,
  required bool canViewReport,
}) {
  final uid = patientUserId?.trim() ?? '';
  if (uid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Patient record is not linked to this appointment yet.')),
    );
    return;
  }
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (ctx) => DoctorPatientClinicalPage(
        patientUserId: uid,
        patientNameFallback: patientName,
        appointmentDateTime: appointmentDateTime,
        reason: reason,
        canViewReport: canViewReport,
      ),
    ),
  );
}

bool doctorAppointmentAllowsClinicalView(String statusLabel) {
  final s = statusLabel.trim().toLowerCase();
  return s == 'confirmed' || s == 'accepted';
}

/// Unique patients with at least one confirmed appointment for this doctor.
List<DoctorPracticePatientRow> practicePatientsFromAppointmentDocs(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final byUid = <String, _PracticeAgg>{};
  for (final d in docs) {
    final m = d.data();
    final st = (m['status'] ?? '').toString().trim().toLowerCase();
    if (st != 'confirmed' && st != 'accepted') continue;
    final uid = (m['userId'] ?? '').toString().trim();
    if (uid.isEmpty) continue;
    final rawName = (m['patientName'] ?? m['patient_name'] ?? '').toString().trim();
    final name = rawName.isNotEmpty ? rawName : 'Patient';
    final date = (m['date'] ?? '').toString().trim();
    final time = (m['timeSlot'] ?? '').toString().trim();
    final visitLabel = [date, time].where((e) => e.isNotEmpty).join(' · ');
    byUid.putIfAbsent(uid, () => _PracticeAgg(uid: uid, displayName: name));
    final agg = byUid[uid]!;
    agg.consultations++;
    if (visitLabel.isNotEmpty) {
      if (agg.lastVisitLabel == null || visitLabel.compareTo(agg.lastVisitLabel!) > 0) {
        agg.lastVisitLabel = visitLabel;
      }
    }
    if (rawName.isNotEmpty) agg.displayName = rawName;
  }
  final rows = byUid.values
      .map(
        (a) => DoctorPracticePatientRow(
          userId: a.uid,
          displayName: a.displayName,
          lastVisit: a.lastVisitLabel ?? '—',
          consultations: a.consultations,
        ),
      )
      .toList();
  rows.sort((a, b) => b.lastVisit.compareTo(a.lastVisit));
  return rows;
}

class DoctorPracticePatientRow {
  const DoctorPracticePatientRow({
    required this.userId,
    required this.displayName,
    required this.lastVisit,
    required this.consultations,
  });

  final String userId;
  final String displayName;
  final String lastVisit;
  final int consultations;
}

class _PracticeAgg {
  _PracticeAgg({required this.uid, required this.displayName});

  final String uid;
  String displayName;
  String? lastVisitLabel;
  int consultations = 0;
}
