import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
import '../utils/scalp_issue_recommendation_text.dart';
import '../utils/scalp_report_pdf.dart';
import '../widgets/patient_web_scaffold.dart';

DateTime? _tsToDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

String? scalpImageUrlFrom(Map<String, dynamic> d) {
  final summary = d['summary'];
  // Prefer URL that was uploaded from the AI overlay JPEG (not the raw camera file).
  for (final key in ['overlayImageUrl', 'overlayScalpImageUrl', 'scalpImageUrl', 'imageUrl', 'scalpPhotoUrl', 'photoUrl']) {
    final v = d[key]?.toString().trim();
    if (v != null && v.isNotEmpty && (v.startsWith('http://') || v.startsWith('https://'))) {
      return v;
    }
  }
  if (summary is Map) {
    for (final key in ['overlayImageUrl', 'overlayScalpImageUrl', 'scalpImageUrl', 'imageUrl', 'scalpPhotoUrl', 'photoUrl']) {
      final v = summary[key]?.toString().trim();
      if (v != null && v.isNotEmpty && (v.startsWith('http://') || v.startsWith('https://'))) {
        return v;
      }
    }
  }
  for (final key in ['scalpImageUrl', 'imageUrl', 'scalpPhotoUrl', 'photoUrl']) {
    final v = d[key]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

Uint8List? scalpImageBytesFromDoc(Map<String, dynamic> d) {
  String normalizeBase64(String raw) {
    final trimmed = raw.trim();
    final comma = trimmed.indexOf(',');
    final payload = (trimmed.startsWith('data:') && comma >= 0)
        ? trimmed.substring(comma + 1)
        : trimmed;
    return payload.replaceAll('\n', '').replaceAll('\r', '');
  }

  final summary = d['summary'];
  for (final key in [
    'overlayImageBase64',
    'overlay_image_base64',
    'analyzedImageBase64',
    'scalpImageBase64',
    'imageBase64',
  ]) {
    final b64 = d[key]?.toString();
    if (b64 == null || b64.isEmpty) continue;
    try {
      return Uint8List.fromList(base64Decode(normalizeBase64(b64)));
    } catch (_) {}
  }
  if (summary is Map) {
    for (final key in [
      'overlayImageBase64',
      'overlay_image_base64',
      'analyzedImageBase64',
      'scalpImageBase64',
      'imageBase64',
    ]) {
      final b64 = summary[key]?.toString();
      if (b64 == null || b64.isEmpty) continue;
      try {
        return Uint8List.fromList(base64Decode(normalizeBase64(b64)));
      } catch (_) {}
    }
  }
  return null;
}

String cleanRecommendationLine(String raw) {
  var s = raw.trim();
  s = s.replaceAll(RegExp(r'\\text\{([^}]*)\}'), r'$1');
  s = s.replaceAll(RegExp(r'[✓✔✅]\s*'), '');
  s = s.replaceFirst(RegExp(r'^[•\-\u2022\u00B7]\s*'), '');
  // PDF default fonts often drop Unicode dashes; normalize for display/print.
  s = s.replaceAll('\u2013', '-').replaceAll('\u2014', '-').replaceAll('\u00a0', ' ');
  return s.trim();
}

List<Map<String, dynamic>> _defaultIssues() => [];

List<String> _defaultRecommendations() => [];

bool _overlayIsStale(Map<String, dynamic> d) {
  String? v = d['overlayPipelineVersion']?.toString();
  final summary = d['summary'];
  if ((v == null || v.isEmpty) && summary is Map) {
    v = summary['overlayPipelineVersion']?.toString();
  }
  if (v == null || v.isEmpty) return true;
  return v != 'v8_damage_contours' &&
      v != 'v7_evidence_metrics' &&
      v != 'v6_cnn_crown_split' &&
      v != 'v5_red_orange_split' &&
      v != 'v4_density_split' &&
      v != 'v3_red_orange_teal';
}

class ScalpReportDetailScreen extends StatefulWidget {
  const ScalpReportDetailScreen({super.key, required this.reportId});

  final String reportId;

  @override
  State<ScalpReportDetailScreen> createState() => _ScalpReportDetailScreenState();
}

class _ScalpReportDetailScreenState extends State<ScalpReportDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = context.read<AuthProvider>().userId;
    if (uid == null || uid.isEmpty || !FirebaseService.isInitialized) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }
    final snap = await FirebaseService.getPatientReport(uid, widget.reportId);
    if (!mounted) return;
    if (snap == null || !snap.exists) {
      setState(() {
        _loading = false;
        _error = 'Report not found.';
      });
      return;
    }
    setState(() {
      _d = snap.data();
      _loading = false;
      _error = null;
    });
  }

  Color _scoreColor(int overall) {
    if (overall >= 70) return const Color(0xFF2E7D32);
    if (overall >= 45) return const Color(0xFFE65100);
    return const Color(0xFFC62828);
  }

  Future<Uint8List?> _scalpImageBytesForPdf() async {
    final d = _d;
    if (d == null) return null;
    final fromDoc = scalpImageBytesFromDoc(d);
    if (fromDoc != null && fromDoc.isNotEmpty) return fromDoc;
    final url = scalpImageUrlFrom(d);
    if (url == null || url.isEmpty) return null;
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) return res.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<void> _sharePdfFile(Uint8List bytes) async {
    final name = 'scalp_report_${widget.reportId}.pdf';
    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: name);
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$name';
    await File(path).writeAsBytes(bytes);
    await Share.shareXFiles([XFile(path)], subject: 'AI Scalp Analysis Report');
  }

  Future<void> _shareOrDownload({required bool share}) async {
    final d = _d;
    if (d == null) return;
    final created = _tsToDate(d['createdAt']) ?? DateTime.now();
    final dateStr = DateFormat('d MMM y').format(created);
    final timeStr = DateFormat('HH:mm').format(created);
    final patientName = d['patientDisplayName']?.toString() ?? 'Patient';
    final age = (d['patientAge'] as num?)?.round() ?? 0;
    final gender = d['patientGender']?.toString() ?? '—';
    final overall = (d['overallScore'] as num?)?.round() ?? (d['averageScore'] as num?)?.round() ?? 0;
    final strength = (d['strength'] as num?)?.round() ?? 0;
    final scalp = (d['scalpHealth'] as num?)?.round() ?? (d['scalp'] as num?)?.round() ?? 0;
    final summaryPdf = (d['summary'] is Map) ? Map<String, dynamic>.from(d['summary'] as Map) : <String, dynamic>{};
    final damage = (d['hairDamage'] as num?)?.round() ??
        (d['damage'] as num?)?.round() ??
        (summaryPdf['hairDamageLevel'] as num?)?.round() ??
        0;
    final fall = (d['hairFallRisk'] as num?)?.round() ??
        (d['fall'] as num?)?.round() ??
        (summaryPdf['hairFallRisk'] as num?)?.round() ??
        0;
    final graft = d['graftEstimateText']?.toString() ?? '1,800 - 2,200';
    final recsPdf = _parseRecs(d['recommendations']);
    final recsPdfFb = recsPdf.isNotEmpty ? recsPdf : _parseRecs(summaryPdf['recommendations']);
    final issues = scalpReportIssuesTableFromDoc(d, recsPdfFb, damage, fall);
    final recs = recsPdfFb;
    final imgBytes = await _scalpImageBytesForPdf();
    final bytes = await buildScalpAnalysisReportPdf(
      patientName: patientName,
      dateStr: dateStr,
      timeStr: timeStr,
      patientAge: age,
      patientGender: gender,
      overallScore: overall,
      strength: strength,
      scalp: scalp,
      damage: damage,
      fall: fall,
      graftEstimateText: graft,
      issues: issues,
      recommendations: recs,
      scalpImageBytes: imgBytes,
    );
    if (!mounted) return;
    if (share) {
      await _sharePdfFile(bytes);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    }
  }

  List<Map<String, dynamic>> _parseIssues(dynamic raw) {
    if (raw is! List) return _defaultIssues();
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) {
        out.add({
          'issue': e['issue']?.toString() ?? '',
          'severity': e['severity']?.toString() ?? '',
          'location': e['location']?.toString() ?? '',
          'recommendation': e['recommendation']?.toString() ?? '',
          'confidencePct': e['confidencePct'] ?? e['confidence'] ?? '',
        });
      }
    }
    return out.isEmpty ? _defaultIssues() : out;
  }

  List<String> _parseRecs(dynamic raw) {
    if (raw is! List) return _defaultRecommendations();
    final out = <String>[];
    for (final e in raw) {
      if (e != null) out.add(cleanRecommendationLine(e.toString()));
    }
    return out.isEmpty ? _defaultRecommendations() : out;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return PatientWebScaffold(
        currentRoute: '/my-report',
        body: const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      );
    }
    if (_error != null) {
      return PatientWebScaffold(
        currentRoute: '/my-report',
        body: Center(child: Text(_error!)),
      );
    }
    final d = _d!;
    final created = _tsToDate(d['createdAt']) ?? DateTime.now();
    final dateTimeLine = '${DateFormat('d MMM y').format(created)} at ${DateFormat('HH:mm').format(created)}';
    final patientName = d['patientDisplayName']?.toString() ?? 'Patient';
    final age = (d['patientAge'] as num?)?.round();
    final gender = d['patientGender']?.toString() ?? 'Not specified';
    final summary = (d['summary'] is Map) ? Map<String, dynamic>.from(d['summary'] as Map) : const <String, dynamic>{};
    final metrics = (summary['metrics'] is Map) ? Map<String, dynamic>.from(summary['metrics'] as Map) : const <String, dynamic>{};
    int metricRound(List<String> keys) {
      for (final k in keys) {
        final v = d[k] ?? summary[k] ?? metrics[k];
        if (v is num) return v.round();
      }
      return 0;
    }

    final strength = metricRound(['strength', 'hairStrength', 'hair_strength']);
    final scalp = metricRound(['scalpHealth', 'scalp', 'scalp_health']);
    final damage = metricRound(['hairDamage', 'damage', 'hairDamageLevel', 'hair_damage_level']);
    final fall = metricRound(['hairFallRisk', 'fall', 'hair_fall_risk']);
    final baldRatioPct = () {
      final br = d['baldRatio'] ?? d['bald_ratio'] ?? summary['baldRatio'] ?? summary['bald_ratio'];
      if (br is num) return (br * (br <= 1 ? 100 : 1)).round();
      return null;
    }();
    final overall = (d['overallScore'] as num?)?.round() ??
        (d['averageScore'] as num?)?.round() ??
        ((strength + scalp + (100 - damage) + (100 - fall)) / 4).round();
    final gm = summary['graftMin'] ?? summary['graft_min'];
    final gx = summary['graftMax'] ?? summary['graft_max'];
    final graft = d['graftEstimateText']?.toString() ??
        ((gm != null && gx != null) ? '$gm - $gx' : 'Not available');
    final recs = _parseRecs(d['recommendations']);
    final recsFallback = recs.isNotEmpty ? recs : _parseRecs(summary['recommendations']);
    // Prefer summary.conditions + saved recommendations so we are not stuck on an old `issues` snapshot.
    final tableIssues = scalpReportIssuesTableFromDoc(d, recsFallback, damage, fall);
    final listRecs = recsFallback;
    final scalpUrl = scalpImageUrlFrom(d);
    final scalpMem = scalpImageBytesFromDoc(d);
    final gaugeColor = _scoreColor(overall);
    final patientLine = 'Patient: $patientName | Age: ${age ?? '—'} | Gender: $gender';

    final tableMinWidth = math.max(MediaQuery.sizeOf(context).width - 32, 720.0);

    return PatientWebScaffold(
      currentRoute: '/my-report',
      extraScrollBottomPadding: 80,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/my-report');
                  }
                },
              ),
              const Expanded(
                child: Text(
                  'AI Scalp Analysis Report',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black),
                ),
              ),
              TextButton(
                onPressed: () => _shareOrDownload(share: false),
                style: TextButton.styleFrom(foregroundColor: Colors.black87, padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.picture_as_pdf_outlined, size: 18, color: Colors.black87),
                    SizedBox(width: 4),
                    Text('Download PDF', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateTimeLine, style: TextStyle(color: Colors.grey.shade700, fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 10),
                Text(patientLine, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87, height: 1.35)),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Overall hair health score', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(
                            '$overall / 100',
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: gaugeColor, height: 1.1),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 96,
                            height: 96,
                            child: CircularProgressIndicator(
                              value: (overall.clamp(0, 100)) / 100.0,
                              strokeWidth: 6,
                              backgroundColor: gaugeColor.withValues(alpha: 0.2),
                              valueColor: AlwaysStoppedAnimation<Color>(gaugeColor),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$overall', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                              const Text('/100', style: TextStyle(fontSize: 10, color: Colors.black54)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            crossAxisAlignment: CrossAxisAlignment.start,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Scalp photo (highlighted)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                if (_overlayIsStale(d)) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: const Text(
                      'This report uses an older saved overlay (yellow/teal). Run a new scan from My Scans to refresh colors (red / orange / teal).',
                      style: TextStyle(fontSize: 12, height: 1.35),
                    ),
                  ),
                ] else if (d['hasAiOverlay'] != true &&
                    (summary['hasAiOverlay'] != true) &&
                    (scalpMem == null || scalpMem.isEmpty)) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: const Text(
                      'No AI trace overlay was saved for this report (raw photo only). Run a new scan from My Scans with the backend running on port 8000.',
                      style: TextStyle(fontSize: 12, height: 1.35),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 280,
                    child: scalpMem != null && scalpMem.isNotEmpty
                        ? Image.memory(
                            scalpMem,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: 280,
                          )
                        : (scalpUrl != null && scalpUrl.isNotEmpty
                            ? Image.network(
                                scalpUrl,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                height: 280,
                                errorBuilder: (_, __, ___) => ColoredBox(
                                  color: Colors.grey.shade200,
                                  child: Icon(Icons.broken_image_outlined, size: 48, color: Colors.grey.shade500),
                                ),
                              )
                            : ColoredBox(
                                color: Colors.grey.shade200,
                                child: Center(
                                  child: Icon(Icons.image_not_supported_outlined, size: 48, color: Colors.grey.shade500),
                                ),
                              )),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Overlay shown above is generated by backend AI from this uploaded image.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            crossAxisAlignment: CrossAxisAlignment.start,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Key metrics', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, c) {
                    final gap = 10.0;
                    final w = c.maxWidth;
                    final tileW = w < 360 ? w : (w - gap) / 2;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        SizedBox(width: tileW, child: _metricCell('Hair Strength', strength, const Color(0xFF59C6B0))),
                        SizedBox(width: tileW, child: _metricCell('Scalp Health', scalp, const Color(0xFFB76BCA))),
                        SizedBox(width: tileW, child: _metricCell('Hair Damage Level', damage, const Color(0xFF7B9ACD))),
                        SizedBox(width: tileW, child: _metricCell('Hair Fall Risk', fall, const Color(0xFFB7BD56))),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'Hair Strength: $strength% | Scalp Health: $scalp% | Hair Damage: $damage% | Hair Fall Risk: $fall%',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade800, height: 1.4),
                  softWrap: true,
                ),
                if (baldRatioPct != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Scores are computed from this photo by the AI backend (visible thinning ~$baldRatioPct% of frame).',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            crossAxisAlignment: CrossAxisAlignment.start,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Detected issues', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableMinWidth,
                    child: Table(
                      border: TableBorder.all(color: Colors.grey.shade400),
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(1.1),
                        2: FlexColumnWidth(1.2),
                        3: FlexColumnWidth(2.2),
                        4: FlexColumnWidth(0.9),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: Colors.grey.shade200),
                          children: [
                            _th('Issue'),
                            _th('Severity'),
                            _th('Location'),
                            _th('Recommendation'),
                            _th('Confidence %'),
                          ],
                        ),
                        ...tableIssues.map(
                          (row) => TableRow(
                            children: [
                              _td(row['issue']?.toString() ?? ''),
                              _td(row['severity']?.toString() ?? ''),
                              _td(row['location']?.toString() ?? ''),
                              _td(row['recommendation']?.toString() ?? ''),
                              _td('${row['confidencePct']}%'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Text(
              'Estimated grafts needed: $graft',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          const SizedBox(height: 12),
          _card(
            crossAxisAlignment: CrossAxisAlignment.start,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Personalized recommendations', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 12),
                ...(listRecs.isEmpty ? ['No recommendations available for this report.'] : listRecs).map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Icon(Icons.circle, size: 6, color: Colors.grey.shade800),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(r, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, height: 1.4)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'This is an AI-generated report for informational purposes only. Not a substitute for professional medical advice.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.35),
          ),
          const SizedBox(height: 20),
          _blackBtn(
            label: 'Book Appointment',
            onTap: () => context.go('/my-appointments'),
          ),
          const SizedBox(height: 10),
          _blackBtn(
            label: 'New Scan',
            onTap: () => context.go('/my-scans'),
          ),
          const SizedBox(height: 10),
          _blackBtn(
            label: 'Share Report',
            onTap: () => _shareOrDownload(share: true),
          ),
        ],
      ),
    );
  }

  static Widget _metricCell(String label, int pct, Color ring) {
    final v = (pct.clamp(0, 100)) / 100.0;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Row(
            children: [
              Text('$pct%', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const Spacer(),
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  value: v,
                  strokeWidth: 4,
                  backgroundColor: ring.withValues(alpha: 0.22),
                  valueColor: AlwaysStoppedAnimation<Color>(ring),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _th(String t) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }

  static Widget _td(String t) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(t, style: const TextStyle(fontSize: 11, height: 1.25)),
    );
  }

  static Widget _card({required Widget child, CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.stretch}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }

  static Widget _blackBtn({required String label, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
