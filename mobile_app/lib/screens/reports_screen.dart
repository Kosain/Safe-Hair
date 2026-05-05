import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/app_colors.dart';
import '../core/nav_helper.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;

  DateTime _reportDate(Map<String, dynamic> r) {
    final raw = (r['createdAt'] ?? r['date'] ?? '').toString();
    final dt = DateTime.tryParse(raw);
    return dt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<Map<String, dynamic>> _normalizeReports(List<Map<String, dynamic>> input) {
    if (input.isEmpty) return input;
    final sorted = [...input];
    sorted.sort((a, b) => _reportDate(b).compareTo(_reportDate(a)));

    // Keep only the latest scalp analysis report; keep all other report types.
    // Some legacy rows may have varying `type` values, so also use title fallback.
    bool keptScalp = false;
    final out = <Map<String, dynamic>>[];
    for (final r in sorted) {
      final type = (r['type'] ?? '').toString().toLowerCase().trim();
      final title = (r['title'] ?? '').toString().toLowerCase().trim();
      final isScalpReport = type == 'scalp_analysis' ||
          type == 'scalp-analysis' ||
          type == 'analysis' ||
          title.contains('scalp analysis');
      if (isScalpReport) {
        if (keptScalp) continue;
        keptScalp = true;
      }
      out.add(r);
    }
    return out;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reports.isEmpty && _loading) _loadReports();
  }

  void _loadReports() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    // Use backend reports only when Firebase is unavailable.
    if (!FirebaseService.isInitialized) {
      try {
        final apiReports = await ApiService().getMyReports(userId: userId).timeout(const Duration(seconds: 8));
        if (apiReports.isNotEmpty) {
          if (mounted) {
            setState(() {
              _reports = _normalizeReports(
                apiReports.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
              );
              _loading = false;
            });
          }
          return;
        }
      } catch (_) {}
    }

    if (FirebaseService.isInitialized) {
      FirebaseService.getReports(userId).listen((snap) {
        if (mounted) {
          setState(() {
            _reports = _normalizeReports(
              snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
            );
            _loading = false;
          });
        }
      });
    } else {
      setState(() => _loading = false);
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
        leading: IconButton(
          onPressed: () => backOrGo(context, '/dashboard'),
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textDark),
        ),
        title: Text('My Reports', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _reports.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.description, size: 64, color: AppColors.textGrey),
                          const SizedBox(height: 16),
                          Text('No reports yet', style: TextStyle(fontSize: 16, color: AppColors.textGrey)),
                          const SizedBox(height: 8),
                          Text('Complete a scalp analysis or consultation\nto generate reports', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textGrey)),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () => context.go('/scalp-analyzer'),
                            child: const Text('Start Analysis'),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_reports.length} report(s)', style: TextStyle(fontSize: 14, color: AppColors.textGrey)),
                          const SizedBox(height: 16),
                          ..._reports.map((r) => _ReportCard(
                                report: r,
                                onTap: () => _showReportDetail(context, r),
                              )),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
    );
  }

  void _showReportDetail(BuildContext context, Map<String, dynamic> report) {
    final summary = report['summary'] as Map<String, dynamic>? ?? {};
    final recommendations = List<String>.from(report['recommendations'] ?? []);
    final overlayBase64 = (report['overlay_image_base64'] ?? report['overlayImageBase64'])?.toString();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.textGrey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 20),
              Text(report['title'] ?? 'Report', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textDark)),
              const SizedBox(height: 8),
              Text(report['type'] ?? '', style: TextStyle(fontSize: 14, color: AppColors.textGrey)),
              const SizedBox(height: 20),
              if (overlayBase64 != null && overlayBase64.isNotEmpty) ...[
                Text(
                  'Bald Area Highlight',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    base64Decode(overlayBase64),
                    fit: BoxFit.contain,
                    height: 220,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (summary.isNotEmpty) ...[
                Text('Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                const SizedBox(height: 8),
                ...summary.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('${e.key}: ${e.value}', style: TextStyle(color: AppColors.textGrey)),
                    )),
                const SizedBox(height: 16),
              ],
              if (recommendations.isNotEmpty) ...[
                Text('Recommendations', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                const SizedBox(height: 8),
                ...recommendations.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, size: 16, color: Colors.teal),
                          const SizedBox(width: 8),
                          Expanded(child: Text(r, style: TextStyle(color: AppColors.textGrey))),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  final VoidCallback onTap;

  const _ReportCard({required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final type = report['type'] ?? 'scalp_analysis';
    final icon = type == 'consultation' ? Icons.medical_services : Icons.analytics;
    final date = report['createdAt'] ?? report['date'] ?? '';
    final dateStr = date.toString().length > 10 ? date.toString().substring(0, 10) : date.toString();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.teal.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(icon, color: Colors.teal, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(report['title'] ?? 'Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                  Text(dateStr, style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textGrey),
          ],
        ),
      ),
    );
  }
}
