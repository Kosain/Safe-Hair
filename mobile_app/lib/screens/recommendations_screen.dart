import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/app_colors.dart';
import '../core/nav_helper.dart';
import '../core/recommendations_data.dart';
import '../models/scalp_analysis_model.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';

class RecommendationsScreen extends StatefulWidget {
  final ScalpAnalysisModel? analysis;

  const RecommendationsScreen({super.key, this.analysis});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  ScalpAnalysisModel? _analysis;
  List<Map<String, dynamic>> _recentAnalyses = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_analysis == null && widget.analysis != null) _analysis = widget.analysis;
    _loadRecentAnalyses();
  }

  void _loadRecentAnalyses() {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null || !FirebaseService.isInitialized) return;
    FirebaseService.getScalpAnalyses(userId).listen((snap) {
      if (mounted) {
        setState(() {
          _recentAnalyses = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          if (_analysis == null && _recentAnalyses.isNotEmpty) {
            _analysis = ScalpAnalysisModel.fromMap(_recentAnalyses.first);
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final analysis = _analysis ?? RecommendationsData.defaultAnalysis;

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
        title: Text('Recommendations', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
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
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.teal.withOpacity(0.2), shape: BoxShape.circle),
                            child: const Icon(Icons.lightbulb, color: Colors.teal, size: 28),
                          ),
                          const SizedBox(width: 12),
                          Text('Personalized for You', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Based on your scalp analysis:', style: TextStyle(fontSize: 14, color: AppColors.textGrey)),
                      const SizedBox(height: 12),
                      ...analysis.recommendations.asMap().entries.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(color: AppColors.darkButton, shape: BoxShape.circle),
                                  child: Center(child: Text('${e.key + 1}', style: const TextStyle(color: AppColors.white, fontSize: 12))),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(e.value, style: TextStyle(fontSize: 14, color: AppColors.textDark, height: 1.4))),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.camera_alt,
                        label: 'New Analysis',
                        onTap: () => context.go('/scalp-analyzer'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.calendar_today,
                        label: 'Book Consultation',
                        onTap: () => context.push('/doctors'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.menu_book,
                        label: 'Guidelines',
                        onTap: () => context.push('/guidelines'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.description,
                        label: 'My Reports',
                        onTap: () => context.push('/reports'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionCard({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: AppColors.darkButton),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textDark)),
          ],
        ),
      ),
    );
  }
}
