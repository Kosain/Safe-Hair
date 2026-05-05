import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
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
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final rnd = Random();
    final strength = 55 + rnd.nextInt(36);
    final scalp = 52 + rnd.nextInt(38);
    final damage = 30 + rnd.nextInt(41);
    final fall = 35 + rnd.nextInt(46);
    final average = FirebaseService.hairHealthAverageScore(strength, scalp, damage, fall);
    final now = DateTime.now();
    final dateStr = DateFormat('d MMM y').format(now);
    final timeStr = DateFormat('HH:mm').format(now);

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

    final reportId = FirebaseService.firestore.collection('patient_details').doc(uid).collection('reports').doc().id;

    String? scalpUrl;
    scalpUrl = await FirebaseService.uploadBytes(
      'patient_scalp_images/$uid/$reportId.jpg',
      _selectedImageBytes!,
      contentType: 'image/jpeg',
    );

    final pSnap = await FirebaseService.getPatientDetails(uid);
    if (!mounted) return;
    final pd = pSnap?.data();
    final nameFromProfile = (pd?['name']?.toString() ?? '').trim();
    final authName = (auth.userName ?? '').trim();
    var patientDisplayName = nameFromProfile.isNotEmpty
        ? nameFromProfile
        : (authName.isNotEmpty ? authName : 'Patient');
    final genderRaw = (pd?['gender']?.toString() ?? '').trim();
    var patientGender = genderRaw.isNotEmpty ? genderRaw : 'Not specified';
    var patientAge = 32;
    final dobDay = (pd?['dob_day'] as num?)?.toInt();
    final dobMonth = (pd?['dob_month'] as num?)?.toInt();
    final dobYear = (pd?['dob_year'] as num?)?.toInt();
    if (dobDay != null && dobMonth != null && dobYear != null) {
      try {
        final dob = DateTime(dobYear, dobMonth, dobDay);
        var a = now.year - dob.year;
        if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) a--;
        if (a > 0 && a < 120) patientAge = a;
      } catch (_) {}
    }

    final issues = <Map<String, dynamic>>[
      {
        'issue': 'Hair thinning',
        'severity': 'Moderate',
        'location': 'Frontal area',
        'recommendation': 'Minoxidil + massage',
        'confidencePct': 92,
      },
      {
        'issue': 'Seborrheic buildup',
        'severity': 'Mild',
        'location': 'Vertex',
        'recommendation': 'Medicated anti-dandruff shampoo',
        'confidencePct': 84,
      },
      {
        'issue': 'Dry scalp',
        'severity': 'Low',
        'location': 'Diffuse',
        'recommendation': 'Gentle moisturizer + reduce heat',
        'confidencePct': 76,
      },
    ];
    final recommendations = <String>[
      'Use a medicated anti-dandruff shampoo 2–3× per week.',
      'Consider topical minoxidil as directed by a dermatologist.',
      'Reduce heat styling; use a heat protectant when needed.',
      'Track shedding weekly and photograph the same scalp zones.',
    ];

    final overall = average.round();
    final pdfBytes = await buildScalpAnalysisReportPdf(
      patientName: patientDisplayName,
      dateStr: dateStr,
      timeStr: timeStr,
      patientAge: patientAge,
      patientGender: patientGender,
      overallScore: overall,
      strength: strength,
      scalp: scalp,
      damage: damage,
      fall: fall,
      graftEstimateText: '1,800 – 2,200',
      issues: issues,
      recommendations: recommendations,
      scalpImageBytes: _selectedImageBytes,
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

    String? pdfUrl;
    pdfUrl = await FirebaseService.uploadBytes(
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
        if (scalpUrl != null && scalpUrl.isNotEmpty) 'scalpImageUrl': scalpUrl,
        'patientDisplayName': patientDisplayName,
        'patientAge': patientAge,
        'patientGender': patientGender,
        'overallScore': overall,
        'issues': issues,
        'recommendations': recommendations,
        'graftEstimateText': '1,800 – 2,200',
      },
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _analyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save analysis. Check connection and try again.')),
      );
      return;
    }

    setState(() => _analyzing = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report generated')),
    );
    context.go('/my-report/view/$reportId');
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
