import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../utils/scalp_api_normalize.dart';
import '../utils/scalp_issue_recommendation_text.dart';
import '../utils/scalp_report_pdf.dart';
import '../widgets/patient_web_scaffold.dart';

class PatientMyScansScreen extends StatefulWidget {
  const PatientMyScansScreen({super.key});

  @override
  State<PatientMyScansScreen> createState() => _PatientMyScansScreenState();
}

class _PatientMyScansScreenState extends State<PatientMyScansScreen> {
  final ImagePicker _picker = ImagePicker();
  Uint8List? _selectedImageBytes;
  bool _analyzing = false;

  String _normalizeBase64(String raw) {
    final trimmed = raw.trim();
    final comma = trimmed.indexOf(',');
    final payload = (trimmed.startsWith('data:') && comma >= 0)
        ? trimmed.substring(comma + 1)
        : trimmed;
    return payload.replaceAll('\n', '').replaceAll('\r', '');
  }

  Future<void> _pickImage(ImageSource source) async {
    final xFile = await _picker.pickImage(source: source, maxWidth: 900);
    if (xFile == null) return;
    final bytes = await xFile.readAsBytes();
    if (!mounted) return;
    setState(() => _selectedImageBytes = bytes);
  }

  Future<void> _analyzeWithAI() async {
    if (_selectedImageBytes == null) return;

    setState(() => _analyzing = true);
    try {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final uid = auth.userId;
      if (uid == null || uid.isEmpty || !FirebaseService.isInitialized) {
        if (!mounted) return;
        setState(() => _analyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in with Firebase enabled to save your analysis and reports.')),
        );
        return;
      }

      final pSnap = await FirebaseService.getPatientDetails(uid);
      if (!mounted) return;
      final pd = pSnap?.data();
      String? profileGender;
      final gr = (pd?['gender']?.toString() ?? '').trim();
      if (gr.isNotEmpty) profileGender = gr;

      final now = DateTime.now();
      int? profileAge;
      final dobDay = (pd?['dob_day'] as num?)?.toInt();
      final dobMonth = (pd?['dob_month'] as num?)?.toInt();
      final dobYear = (pd?['dob_year'] as num?)?.toInt();
      if (dobDay != null && dobMonth != null && dobYear != null) {
        try {
          final dob = DateTime(dobYear, dobMonth, dobDay);
          var a = now.year - dob.year;
          if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) a--;
          if (a > 0 && a < 120) profileAge = a;
        } catch (_) {}
      }

      final api = await ApiService().analyzeScalpImage(
        _selectedImageBytes!,
        userId: uid,
        patientGender: profileGender,
        patientAge: profileAge,
      );
      if (api == null || api['_error'] != null) {
        throw Exception(api?['_error']?.toString() ?? 'AI API returned no result.');
      }
      final norm = normalizeScalpApiResponse(api);

      final strength = scalpApiNum(norm, const ['hair_strength', 'hairStrength'])?.round() ?? 0;
      final scalp = scalpApiNum(norm, const ['scalp_health', 'scalpHealth'])?.round() ?? 0;
      final density = scalpApiNum(norm, const ['hair_density', 'hairDensity'])?.round() ?? 0;
      final moisture = scalpApiNum(norm, const ['moisture_level', 'moistureLevel'])?.round() ?? 0;
      final damage = scalpApiNum(norm, const ['hair_damage_level', 'hairDamageLevel'])?.round() ??
          (100 - density).clamp(0, 100);
      final fall = scalpApiNum(norm, const ['hair_fall_risk', 'hairFallRisk'])?.round() ??
          (100 - scalp).clamp(0, 100);
      final baldRatio = scalpApiNum(norm, const ['bald_ratio', 'baldRatio']);
      final average = FirebaseService.hairHealthAverageScore(strength, scalp, damage, fall);
      final dateStr = DateFormat('d MMM y').format(now);
      final timeStr = DateFormat('HH:mm').format(now);

      final reportId = FirebaseService.firestore.collection('patient_details').doc(uid).collection('reports').doc().id;
      final overlayRaw = (norm['overlay_image_base64'] ?? norm['overlayImageBase64'])?.toString();
      final overlayLegend = norm['overlay_legend'];
      final overlayBase64 =
          (overlayRaw != null && overlayRaw.isNotEmpty) ? _normalizeBase64(overlayRaw) : null;
      final originalBase64 = base64Encode(_selectedImageBytes!);
      final analyzedBase64 =
          (overlayBase64 != null && overlayBase64.isNotEmpty) ? overlayBase64 : originalBase64;
      final overlayPipelineVersion =
          (norm['overlay_pipeline_version'] ?? norm['overlayPipelineVersion'])?.toString() ?? '';
      final hasAiOverlay = (norm['has_ai_overlay'] == true) ||
          (overlayBase64 != null &&
              overlayBase64.isNotEmpty &&
              (overlayLegend is Map
                  ? ((overlayLegend['red'] == true) ||
                      (overlayLegend['orange'] == true) ||
                      (overlayLegend['teal'] == true))
                  : true));

      // Storage must be the AI-highlighted image (not the raw upload).
      final Uint8List scalpUploadBytes = (overlayBase64 != null && overlayBase64.isNotEmpty)
          ? Uint8List.fromList(base64Decode(overlayBase64))
          : _selectedImageBytes!;

      String? scalpUrl = await FirebaseService.uploadBytes(
        'patient_scalp_images/$uid/$reportId.jpg',
        scalpUploadBytes,
        contentType: 'image/jpeg',
      );

      if (!mounted) return;
      final nameFromProfile = (pd?['name']?.toString() ?? '').trim();
      final authName = (auth.userName ?? '').trim();
      final patientDisplayName = nameFromProfile.isNotEmpty
          ? nameFromProfile
          : (authName.isNotEmpty ? authName : 'Patient');
      final genderRaw = (pd?['gender']?.toString() ?? '').trim();
      final patientGender = genderRaw.isNotEmpty ? genderRaw : 'Not specified';
      final patientAge = profileAge ?? 32;

      final recs = List<String>.from(norm['recommendations'] ?? const <String>[]);
      final conds = List<String>.from(norm['conditions'] ?? const <String>[]);
      final reliability =
          (norm['estimate_reliability_percent'] ?? norm['estimateReliabilityPercent'])?.toString() ?? '';
      final view = (norm['view_orientation'] ?? norm['viewOrientation'])?.toString() ?? 'Scalp';
      String inferLocation(String c) {
        final s = c.toLowerCase();
        if (s.contains('temple') || s.contains('frontal') || s.contains('hairline') || s.contains('front')) {
          return 'Frontal area';
        }
        if (s.contains('vertex') || s.contains('crown') || s.contains('top')) {
          return 'Vertex/Crown';
        }
        if (s.contains('diffuse')) return 'Diffuse';
        return view == 'front' ? 'Frontal area' : 'Vertex/Crown';
      }

      final issues = <Map<String, dynamic>>[];
      for (var i = 0; i < conds.length; i++) {
        final c = conds[i].toString();
        issues.add({
          'issue': c,
          'severity': scalpConditionSeverityLabel(c),
          'location': inferLocation(c),
          'recommendation': scalpIssueRecommendationText(recs, i, conds.length),
          'confidencePct': reliability,
        });
      }

      final gm = norm['graft_min'] ?? norm['graftMin'];
      final gx = norm['graft_max'] ?? norm['graftMax'];
      final graftText = (gm != null && gx != null) ? '$gm - $gx' : 'Not available';

      final pdfBytes = await buildScalpAnalysisReportPdf(
        patientName: patientDisplayName,
        dateStr: dateStr,
        timeStr: timeStr,
        patientAge: patientAge,
        patientGender: patientGender,
        overallScore: average.round(),
        strength: strength,
        scalp: scalp,
        damage: damage,
        fall: fall,
        graftEstimateText: graftText,
        issues: issues,
        recommendations: recs,
        scalpImageBytes: overlayBase64 != null && overlayBase64.isNotEmpty
            ? Uint8List.fromList(base64Decode(overlayBase64))
            : _selectedImageBytes,
      );

      String? localFileName;
      if (!kIsWeb) {
        try {
          final dir = await getApplicationDocumentsDirectory();
          final folder = Directory('${dir.path}/reports');
          if (!await folder.exists()) await folder.create(recursive: true);
          localFileName = 'report_${DateTime.now().millisecondsSinceEpoch}.pdf';
          await File('${folder.path}/$localFileName').writeAsBytes(pdfBytes);
        } catch (_) {}
      }

      final pdfUrl = await FirebaseService.uploadBytes(
        'patient_reports/$uid/$reportId.pdf',
        pdfBytes,
        contentType: 'application/pdf',
      );
      if (!mounted) return;

      final ok = await FirebaseService.saveHairAnalysisSession(
        userId: uid,
        strength: strength,
        scalp: scalp,
        damage: damage,
        fall: fall,
        reportDocId: reportId,
        reportPayload: {
          if (pdfUrl != null) 'pdfUrl': pdfUrl,
          if (localFileName != null) 'localPdfFileName': localFileName,
          if (scalpUrl != null && scalpUrl.isNotEmpty) ...{
            'scalpImageUrl': scalpUrl,
            'overlayImageUrl': scalpUrl,
          },
          'hasAiOverlay': hasAiOverlay,
          if (overlayLegend is Map) 'overlayLegend': overlayLegend,
          if (baldRatio != null) 'baldRatio': baldRatio,
          // Keep explicit provenance so report always shows the image tied to this analysis.
          'sourceImageBase64': originalBase64,
          'analyzedImageBase64': analyzedBase64,
          // Backward-compatible keys used by existing report reader.
          'scalpImageBase64': analyzedBase64,
          'imageBase64': analyzedBase64,
          if (overlayBase64 != null && overlayBase64.isNotEmpty) 'overlay_image_base64': overlayBase64,
          if (overlayBase64 != null && overlayBase64.isNotEmpty) 'overlayImageBase64': overlayBase64,
          'patientDisplayName': patientDisplayName,
          'patientAge': patientAge,
          'patientGender': patientGender,
          'overallScore': average.round(),
          'issues': issues,
          'recommendations': recs,
          'graftEstimateText': graftText,
          'overlayPipelineVersion': overlayPipelineVersion.isNotEmpty
              ? overlayPipelineVersion
              : 'v6_cnn_crown_split',
          'summary': {
            'hairStrength': strength,
            'scalpHealth': scalp,
            'hairDensity': density,
            'moistureLevel': moisture,
            'hairDamageLevel': damage,
            'hairFallRisk': fall,
            'conditions': conds,
            'recommendations': recs,
            'graftMin': gm,
            'graftMax': gx,
            'viewOrientation': view,
            'estimateReliabilityPercent': reliability,
            'hasAiOverlay': hasAiOverlay,
            if (baldRatio != null) 'baldRatio': baldRatio,
            if (scalpUrl != null && scalpUrl.isNotEmpty) 'overlayImageUrl': scalpUrl,
            if (overlayBase64 != null && overlayBase64.isNotEmpty) 'overlay_image_base64': overlayBase64,
            if (overlayBase64 != null && overlayBase64.isNotEmpty) 'overlayImageBase64': overlayBase64,
          },
        },
      );
      if (!mounted) return;
      if (!ok) {
        setState(() => _analyzing = false);
        final detail = FirebaseService.lastHairAnalysisSaveError;
        final msg = detail != null && detail.contains('permission-denied')
            ? 'Could not save: Firestore rules blocked write. In Firebase Console publish rules from firebase/firestore.rules.'
            : (detail != null && detail.isNotEmpty)
                ? 'Could not save analysis: $detail'
                : 'Could not save analysis. Check Firebase connection and try again.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      setState(() => _analyzing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI analysis report generated')),
      );
      context.go('/my-report/view/$reportId');
    } catch (e) {
      if (!mounted) return;
      setState(() => _analyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analysis failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _selectedImageBytes != null;
    final canAnalyze = hasImage && !_analyzing;

    return PatientWebScaffold(
      currentRoute: GoRouterState.of(context).matchedLocation,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Get Your AI Scalp Analysis',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.black),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Capture a clear image of your scalp. Our AI analyzes hair strength, scalp health, density, and moisture to provide personalized recommendations.',
                  style: TextStyle(fontSize: 14, color: Color(0xFF666666), height: 1.35),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    width: 250,
                    height: 250,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _selectedImageBytes != null
                        ? Image.memory(_selectedImageBytes!, fit: BoxFit.cover)
                        : const Image(
                            image: AssetImage('assets/images/head.png'),
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: ElevatedButton.icon(
                          onPressed: _analyzing ? null : () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                          label: const Text('Camera', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            fixedSize: const Size(double.infinity, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: ElevatedButton.icon(
                          onPressed: _analyzing ? null : () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library, color: Colors.white, size: 18),
                          label: const Text('Gallery', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            fixedSize: const Size(double.infinity, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: canAnalyze ? _analyzeWithAI : null,
                    icon: _analyzing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                          )
                        : const Icon(Icons.auto_awesome, color: Colors.black87),
                    label: Text(
                      _analyzing ? 'Analyzing...' : 'Analyze with AI',
                      style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFF176),
                      foregroundColor: Colors.black87,
                      disabledBackgroundColor: Colors.grey.shade400,
                      disabledForegroundColor: Colors.grey.shade600,
                      minimumSize: const Size(220, 54),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
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
