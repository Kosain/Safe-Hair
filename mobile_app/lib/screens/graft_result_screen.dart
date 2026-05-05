import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/app_colors.dart';
import '../core/nav_helper.dart';
import '../providers/auth_provider.dart';

/// Splits total graft range into zone estimates (UI breakdown; same order of magnitude as API totals).
Map<String, String> graftZoneBreakdownFromTotal(int totalMin, int totalMax) {
  const labels = ['Front Area', 'Vertex (Crown)', 'Mid-Scalp', 'Back Area'];
  const weights = [0.26, 0.32, 0.24, 0.18];
  final out = <String, String>{};
  var cumMin = 0;
  var cumMax = 0;
  for (var i = 0; i < labels.length; i++) {
    final w = weights[i];
    int zMin;
    int zMax;
    if (i == labels.length - 1) {
      zMin = (totalMin - cumMin).clamp(0, totalMin);
      zMax = (totalMax - cumMax).clamp(zMin, totalMax);
    } else {
      zMin = (totalMin * w).round();
      zMax = (totalMax * w).round();
      cumMin += zMin;
      cumMax += zMax;
    }
    if (zMax < zMin) zMax = zMin;
    out[labels[i]] = '$zMin - $zMax Grafts';
  }
  return out;
}

class GraftResultScreen extends StatelessWidget {
  final String? imageUrl;
  final String? overlayImageBase64;
  final int? totalMin;
  final int? totalMax;
  final Map<String, String>? breakdown;

  const GraftResultScreen({
    super.key,
    this.imageUrl,
    this.overlayImageBase64,
    this.totalMin,
    this.totalMax,
    this.breakdown,
  });

  Uint8List? _overlayBytes() {
    final b64 = overlayImageBase64;
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasApiTotals = totalMin != null && totalMax != null;
    final tMin = hasApiTotals ? totalMin! : null;
    final tMax = hasApiTotals ? totalMax! : null;
    final breakdownMap = breakdown ??
        (hasApiTotals ? graftZoneBreakdownFromTotal(tMin!, tMax!) : null);
    final displayBreakdown = breakdownMap ??
        {
          'Front Area': '—',
          'Vertex (Crown)': '—',
          'Mid-Scalp': '—',
          'Back Area': '—',
        };
    final overlayBytes = _overlayBytes();

    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.primaryGreen,
      appBar: AppBar(
        backgroundColor: AppColors.primaryGreen,
        elevation: 0,
        leading: IconButton(
          onPressed: () => backOrGo(context, '/dashboard'),
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textDark),
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text('Graft Estimated Result', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold)),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout, color: AppColors.textDark),
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              if (context.mounted) context.go('/role');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
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
                  Text('Estimated Graft Needed:', style: TextStyle(fontSize: 14, color: AppColors.textGrey)),
                  const SizedBox(height: 8),
                  Text(
                    hasApiTotals ? '$tMin - $tMax Grafts' : 'Run analysis to see graft range',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textDark),
                  ),
                  if (!hasApiTotals)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Open AI Scalp Analyzer, analyze a photo, then tap “View Graft Estimate”.',
                        style: TextStyle(fontSize: 12, color: AppColors.textGrey),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text('Analyzed scalp (bald region overlay)', style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
                  const SizedBox(height: 8),
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: overlayBytes != null
                        ? Image.memory(
                            overlayBytes,
                            fit: BoxFit.contain,
                            width: double.infinity,
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.face_retouching_natural, size: 56, color: AppColors.textGrey),
                                const SizedBox(height: 8),
                                Text(
                                  'No overlay from last analysis',
                                  style: TextStyle(fontSize: 12, color: AppColors.textGrey),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),
                  Text('Detail BreakDown:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                  const SizedBox(height: 16),
                  ...displayBreakdown.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key, style: TextStyle(color: AppColors.textGrey)),
                          Text(e.value, style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textDark)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.push('/appointment'),
                child: const Text('Book an appointment'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
