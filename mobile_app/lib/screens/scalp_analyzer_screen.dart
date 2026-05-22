import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/app_colors.dart';
import '../core/nav_helper.dart';
import '../models/scalp_analysis_model.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../widgets/animated_primary_button.dart';

class ScalpAnalyzerScreen extends StatefulWidget {
  const ScalpAnalyzerScreen({super.key});

  @override
  State<ScalpAnalyzerScreen> createState() => _ScalpAnalyzerScreenState();
}

class _ScalpAnalyzerScreenState extends State<ScalpAnalyzerScreen> {
  static const String _defaultHeadAsset = 'assets/images/head.png';
  dynamic _image; // File or bytes for web
  String _selectedImagePath = _defaultHeadAsset;
  bool _selectedFromAsset = true;
  List<int>? _imageBytes;
  bool _loading = false;
  ScalpAnalysisModel? _analysisResult;

  double _numOrThrow(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is num) return v.toDouble();
      if (v is String) {
        final p = double.tryParse(v);
        if (p != null) return p;
      }
    }
    throw Exception('Missing AI metric: ${keys.first}');
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: source, maxWidth: 800);
    if (xFile != null) {
      final bytes = await xFile.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _selectedImagePath = xFile.path;
        _selectedFromAsset = false;
        if (!kIsWeb) {
          _image = File(xFile.path);
        } else {
          _image = bytes;
        }
        _analysisResult = null;
      });
    }
  }

  Future<void> _analyze() async {
    if (_imageBytes == null || _imageBytes!.isEmpty) return;
    setState(() => _loading = true);

    try {
      final auth = context.read<AuthProvider>();
      final signedInUid = auth.userId;
      final patientDisplayName = (auth.userName ?? 'Patient').trim();
      final userId = signedInUid ?? 'unknown';

      String? profileGender;
      int? profileAge;
      if (FirebaseService.isInitialized && signedInUid != null && signedInUid.isNotEmpty) {
        final prof = await FirebaseService.getPatientDetails(signedInUid);
        final d = prof?.data();
        final gx = (d?['gender']?.toString() ?? '').trim();
        if (gx.isNotEmpty) profileGender = gx;
        final n = DateTime.now();
        final dd = (d?['dob_day'] as num?)?.toInt();
        final mm = (d?['dob_month'] as num?)?.toInt();
        final yy = (d?['dob_year'] as num?)?.toInt();
        if (dd != null && mm != null && yy != null) {
          try {
            final dob = DateTime(yy, mm, dd);
            var a = n.year - dob.year;
            if (n.month < dob.month || (n.month == dob.month && n.day < dob.day)) a--;
            if (a > 0 && a < 120) profileAge = a;
          } catch (_) {}
        }
      }

      // Call AI analysis API (with timeout in ApiService).
      // Do not use local fake fallback; fail clearly if backend AI is unavailable.
      final apiResult = await ApiService().analyzeScalpImage(
        _imageBytes!,
        userId: userId,
        patientGender: profileGender,
        patientAge: profileAge,
      );
      if (apiResult == null) {
        throw Exception('AI API returned empty response');
      }
      if (apiResult['_error'] != null) {
        throw Exception(apiResult['_error'].toString());
      }

      final analysis = ScalpAnalysisModel(
        id: '',
        userId: userId,
        hairStrength: _numOrThrow(apiResult, const ['hair_strength', 'hairStrength']),
        scalpHealth: _numOrThrow(apiResult, const ['scalp_health', 'scalpHealth']),
        hairDensity: _numOrThrow(apiResult, const ['hair_density', 'hairDensity']),
        moistureLevel: _numOrThrow(apiResult, const ['moisture_level', 'moistureLevel']),
        conditions: List<String>.from(apiResult['conditions'] ?? []),
        recommendations: List<String>.from(apiResult['recommendations'] ?? []),
        createdAt: DateTime.now(),
        baldAreaCm2: (apiResult['bald_area_cm2'] ?? apiResult['baldAreaCm2']) != null
            ? (apiResult['bald_area_cm2'] ?? apiResult['baldAreaCm2']).toDouble()
            : null,
        baldOnlyCm2: (apiResult['bald_only_cm2'] ?? apiResult['baldOnlyCm2']) != null
            ? (apiResult['bald_only_cm2'] ?? apiResult['baldOnlyCm2']).toDouble()
            : null,
        thinAreaCm2: (apiResult['thin_area_cm2'] ?? apiResult['thinAreaCm2']) != null
            ? (apiResult['thin_area_cm2'] ?? apiResult['thinAreaCm2']).toDouble()
            : null,
        graftMin: apiResult['graft_min'] ?? apiResult['graftMin'],
        graftMax: apiResult['graft_max'] ?? apiResult['graftMax'],
        baldRatio: (apiResult['bald_ratio'] ?? apiResult['baldRatio']) != null
            ? (apiResult['bald_ratio'] ?? apiResult['baldRatio']).toDouble()
            : null,
        overlayImageBase64: apiResult['overlay_image_base64'] ?? apiResult['overlayImageBase64'],
        hairAreaCm2: (apiResult['hair_area_cm2'] ?? apiResult['hairAreaCm2']) != null
            ? (apiResult['hair_area_cm2'] ?? apiResult['hairAreaCm2']).toDouble()
            : null,
        estimatedHairCountMin: int.tryParse('${apiResult['estimated_hair_count_min'] ?? ''}'),
        estimatedHairCountMax: int.tryParse('${apiResult['estimated_hair_count_max'] ?? ''}'),
        estimatedHairCount: int.tryParse('${apiResult['estimated_hair_count'] ?? ''}'),
        segmentationMethod: apiResult['segmentation_method']?.toString() ?? apiResult['segmentationMethod']?.toString(),
        hairCountNote: apiResult['hair_count_note']?.toString() ?? apiResult['hairCountNote']?.toString(),
        viewOrientation: apiResult['view_orientation']?.toString() ?? apiResult['viewOrientation']?.toString(),
        analysisSummary: apiResult['analysis_summary']?.toString() ?? apiResult['analysisSummary']?.toString(),
        estimateReliabilityPercent: int.tryParse('${apiResult['estimate_reliability_percent'] ?? apiResult['estimateReliabilityPercent'] ?? ''}'),
        estimateDisclaimer: apiResult['estimate_disclaimer']?.toString() ?? apiResult['estimateDisclaimer']?.toString(),
        overlayLegend: ScalpAnalysisModel.parseOverlayLegend(
          apiResult['overlay_legend'] ?? apiResult['overlayLegend'],
        ),
      );

      // Upload image to Firebase Storage if available (don't block on failure)
      String? imageUrl;
      final isLocalWeb =
          kIsWeb && (Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1');
      if (FirebaseService.isInitialized && !isLocalWeb) {
        try {
          imageUrl = await FirebaseService.uploadImage(
            'scalp/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg',
            Uint8List.fromList(_imageBytes!),
          ).timeout(const Duration(seconds: 15));
        } catch (_) {}
      }

      final data = <String, dynamic>{
        ...analysis.toMap(),
        'imageUrl': imageUrl,
        'userId': userId,
      };

      if (!FirebaseService.isInitialized) {
        await ApiService().saveScalpAnalysis(data).timeout(const Duration(seconds: 10));
      }
      if (FirebaseService.isInitialized) {
        try {
          await FirebaseService.saveScalpAnalysis(data).timeout(const Duration(seconds: 10));
        } catch (_) {}
      }

      // Save as report
      if (FirebaseService.isInitialized) {
        try {
          await FirebaseService.saveReport({
            'userId': userId,
            'type': 'scalp_analysis',
            'title': 'Scalp Analysis Report',
            'date': DateTime.now().toIso8601String(),
            'createdAt': DateTime.now().toIso8601String(),
            // Keep top-level fields for existing report readers.
            'overlay_image_base64': analysis.overlayImageBase64,
            'overlayImageBase64': analysis.overlayImageBase64,
            'scalpImageBase64': base64Encode(_imageBytes!),
            'imageBase64': base64Encode(_imageBytes!),
            'summary': {
              'hairStrength': analysis.hairStrength,
              'scalpHealth': analysis.scalpHealth,
              'hairDensity': analysis.hairDensity,
              'moistureLevel': analysis.moistureLevel,
              'conditions': analysis.conditions,
              'baldAreaCm2': analysis.baldAreaCm2,
              'graftMin': analysis.graftMin,
              'graftMax': analysis.graftMax,
              'baldRatio': analysis.baldRatio,
              'hairAreaCm2': analysis.hairAreaCm2,
              'estimatedHairCountMin': analysis.estimatedHairCountMin,
              'estimatedHairCountMax': analysis.estimatedHairCountMax,
              'estimatedHairCount': analysis.estimatedHairCount,
              'segmentationMethod': analysis.segmentationMethod,
              'overlay_image_base64': analysis.overlayImageBase64,
              'overlayImageBase64': analysis.overlayImageBase64,
            },
            'recommendations': analysis.recommendations,
          }).timeout(const Duration(seconds: 10));
        } catch (_) {}

        // Dashboard reads `patient_details` + `hair_scans` (same as My Scans). Analyzer used to
        // only write `scalp_analyses` / root `reports`, so metrics never refreshed after Analyze here.
        if (signedInUid != null && signedInUid.isNotEmpty) {
          try {
            final strength = analysis.hairStrength.round().clamp(0, 100);
            final scalp = analysis.scalpHealth.round().clamp(0, 100);
            final damage = ((apiResult['hair_damage_level'] ?? apiResult['hairDamageLevel']) as num?)
                    ?.round()
                    .clamp(0, 100) ??
                (100 - analysis.hairDensity).round().clamp(0, 100);
            final fall = ((apiResult['hair_fall_risk'] ?? apiResult['hairFallRisk']) as num?)
                    ?.round()
                    .clamp(0, 100) ??
                (100 - analysis.scalpHealth).round().clamp(0, 100);
            final avg = FirebaseService.hairHealthAverageScore(strength, scalp, damage, fall).round();

            final originalB64 = base64Encode(_imageBytes!);
            var overlayRaw = analysis.overlayImageBase64?.trim();
            if (overlayRaw != null && overlayRaw.startsWith('data:')) {
              final comma = overlayRaw.indexOf(',');
              if (comma >= 0) overlayRaw = overlayRaw.substring(comma + 1);
            }
            overlayRaw = overlayRaw?.replaceAll('\n', '').replaceAll('\r', '');
            final analyzedB64 =
                (overlayRaw != null && overlayRaw.isNotEmpty) ? overlayRaw : originalB64;

            final reportId = FirebaseService.firestore
                .collection('patient_details')
                .doc(signedInUid)
                .collection('reports')
                .doc()
                .id;

            final synced = await FirebaseService.saveHairAnalysisSession(
              userId: signedInUid,
              strength: strength,
              scalp: scalp,
              damage: damage,
              fall: fall,
              reportDocId: reportId,
              reportPayload: {
                'analyzedImageBase64': analyzedB64,
                'scalpImageBase64': analyzedB64,
                'imageBase64': analyzedB64,
                if (overlayRaw != null && overlayRaw.isNotEmpty) 'overlayImageBase64': overlayRaw,
                if (overlayRaw != null && overlayRaw.isNotEmpty) 'overlay_image_base64': overlayRaw,
                'patientDisplayName': patientDisplayName.isNotEmpty ? patientDisplayName : 'Patient',
                'overallScore': avg,
                'issues': const <Map<String, dynamic>>[],
                'recommendations': analysis.recommendations,
                'graftEstimateText': (analysis.graftMin != null && analysis.graftMax != null)
                    ? '${analysis.graftMin} - ${analysis.graftMax}'
                    : 'Not available',
                'summary': {
                  'hairStrength': strength,
                  'scalpHealth': scalp,
                  'hairDensity': analysis.hairDensity.round(),
                  'moistureLevel': analysis.moistureLevel.round(),
                  'hairDamageLevel': damage,
                  'hairFallRisk': fall,
                  'conditions': analysis.conditions,
                  'recommendations': analysis.recommendations,
                  'graftMin': analysis.graftMin,
                  'graftMax': analysis.graftMax,
                  'viewOrientation': analysis.viewOrientation,
                  'estimateReliabilityPercent': analysis.estimateReliabilityPercent,
                  if (overlayRaw != null && overlayRaw.isNotEmpty) 'overlayImageBase64': overlayRaw,
                },
              },
            );
            if (!synced && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Analysis completed, but dashboard metrics could not be saved. Check Firestore rules and try Analyze from My Scans.',
                  ),
                ),
              );
            }
          } catch (e, st) {
            debugPrint('saveHairAnalysisSession from scalp analyzer: $e\n$st');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Dashboard sync failed: $e')),
              );
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _loading = false;
          _analysisResult = analysis;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Analysis failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.primaryGreen,
      appBar: AppBar(
        backgroundColor: AppColors.primaryGreen,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => backOrGo(context, '/dashboard'),
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textDark),
        ),
        // Left-aligned row: back button (leading) + title. No top-right action.
        title: const Text(
          'AI Scalp Analyzer',
          style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Keep heading on one line without truncation by reducing size.
                  const Text(
                    'Get Your AI Scalp Analysis',
                    maxLines: 1,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Capture a clear image of your scalp. Our AI analyzes hair strength, scalp health, density, and moisture to provide personalized recommendations.',
                    style: TextStyle(fontSize: 14, color: AppColors.textGrey, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _selectedFromAsset
                            ? Image.asset(
                                _selectedImagePath,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(color: AppColors.cardBackground),
                              )
                            : (kIsWeb
                                ? Image.memory(Uint8List.fromList(_image as List<int>), fit: BoxFit.cover)
                                : Image.file(File(_selectedImagePath), fit: BoxFit.cover)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton(
                          onPressed: _loading ? null : () => _pickImage(ImageSource.camera),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt, color: Colors.white, size: 19),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Camera',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton(
                          onPressed: _loading ? null : () => _pickImage(ImageSource.gallery),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.photo_library, size: 19, color: Colors.white),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Gallery',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                        ),
                      ),
                    ],
                  ),
                  if (!_selectedFromAsset && _analysisResult == null) ...[
                    const SizedBox(height: 24),
                    Center(
                      child: SizedBox(
                        height: 48,
                        width: 230,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _analyze,
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                )
                              : const Icon(Icons.auto_awesome, color: Colors.black, size: 19),
                          label: const Text(
                            'Analyze with AI',
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFFFF176),
                            foregroundColor: Colors.black,
                            elevation: 3,
                            shadowColor: Colors.deepOrangeAccent.withValues(alpha: 0.35),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
                if (_analysisResult != null) ...[
                  const SizedBox(height: 24),
                  _buildAnalysisResult(_analysisResult!),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: AnimatedPrimaryButton(
                      onPressed: () => context.push(
                        '/graft-result',
                        extra: {
                          'totalMin': _analysisResult!.graftMin,
                          'totalMax': _analysisResult!.graftMax,
                          'overlayImageBase64': _analysisResult!.overlayImageBase64,
                        },
                      ),
                      child: const Text('View Graft Estimate'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () => context.push('/recommendations', extra: {'analysis': _analysisResult}),
                      child: const Text('View Full Recommendations →'),
                    ),
                  ),
                ],
              ],
            ),
      ),
    );
  }

  Widget _buildAnalysisResult(ScalpAnalysisModel a) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.teal),
              const SizedBox(width: 8),
              Text('AI Analysis Results', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
            ],
          ),
          if (a.analysisSummary != null && a.analysisSummary!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.withValues(alpha: 0.22)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Summary', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const SizedBox(height: 6),
                  Text(
                    a.analysisSummary!,
                    style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textDark.withValues(alpha: 0.9)),
                  ),
                  if (a.estimateReliabilityPercent != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Estimate quality score: ${a.estimateReliabilityPercent}% (higher when a trained CNN is used with good data).',
                      style: TextStyle(fontSize: 11, color: AppColors.textGrey, height: 1.35),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (a.estimateDisclaimer != null && a.estimateDisclaimer!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Text(
                a.estimateDisclaimer!,
                style: TextStyle(fontSize: 11, height: 1.35, color: AppColors.textDark.withValues(alpha: 0.88)),
              ),
            ),
          ],
          if (a.overlayImageBase64 != null && a.overlayImageBase64!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              ScalpAnalysisModel.overlayLegendCaption(a.overlayLegend),
              style: TextStyle(fontSize: 12, color: AppColors.textGrey),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                base64Decode(a.overlayImageBase64!),
                fit: BoxFit.contain,
                height: 200,
              ),
            ),
          ],
          if (a.baldAreaCm2 != null ||
              a.graftMin != null ||
              a.graftMax != null ||
              a.estimatedHairCountMin != null ||
              a.estimatedHairCountMax != null) ...[
            const SizedBox(height: 16),
            Text('Bald area & estimates', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (a.baldOnlyCm2 != null && a.thinAreaCm2 != null && a.viewOrientation == 'top')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bald vs thinning', style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                        Text(
                          'Bald ${a.baldOnlyCm2!.toStringAsFixed(1)} · Thin ${a.thinAreaCm2!.toStringAsFixed(1)} cm²',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade800),
                        ),
                      ],
                    ),
                  ),
                if (a.baldAreaCm2 != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.viewOrientation == 'top' ? 'Graft-equivalent area' : 'Bald area',
                          style: TextStyle(fontSize: 11, color: AppColors.textGrey),
                        ),
                        Text('${a.baldAreaCm2!.toStringAsFixed(1)} cm²', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange)),
                      ],
                    ),
                  ),
                if (a.graftMin != null && a.graftMax != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Est. grafts', style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                        Text('${a.graftMin} – ${a.graftMax}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                      ],
                    ),
                  ),
                if (a.estimatedHairCountMin != null && a.estimatedHairCountMax != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Est. hair count (visible region)', style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                        Text('${a.estimatedHairCountMin} – ${a.estimatedHairCountMax} hairs',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                      ],
                    ),
                  ),
              ],
            ),
            if (a.hairCountNote != null && a.hairCountNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(a.hairCountNote!, style: TextStyle(fontSize: 11, color: AppColors.textGrey, height: 1.35)),
            ],
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              _MetricChip('Hair Strength', a.hairStrength, Colors.teal),
              const SizedBox(width: 8),
              _MetricChip('Scalp Health', a.scalpHealth, Colors.pink),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _MetricChip('Hair Density', a.hairDensity, Colors.amber),
              const SizedBox(width: 8),
              _MetricChip('Moisture', a.moistureLevel, Colors.blue),
            ],
          ),
          if (a.conditions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Detected', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
            const SizedBox(height: 4),
            ...a.conditions.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $c', style: TextStyle(color: AppColors.textGrey)),
                )),
          ],
          if (a.recommendations.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Recommendations', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
            const SizedBox(height: 4),
            ...a.recommendations.take(3).map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $r', style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
                )),
          ],
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _MetricChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
            Text('${value.toInt()}%', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

