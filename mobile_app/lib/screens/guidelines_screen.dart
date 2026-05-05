import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_colors.dart';
import '../core/guidelines_data.dart';
import '../core/nav_helper.dart';
import '../models/guideline_model.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';

class GuidelinesScreen extends StatefulWidget {
  const GuidelinesScreen({super.key});

  @override
  State<GuidelinesScreen> createState() => _GuidelinesScreenState();
}

class _GuidelinesScreenState extends State<GuidelinesScreen> {
  List<GuidelineModel> _guidelines = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadGuidelines();
  }

  Future<void> _loadGuidelines() async {
    List<GuidelineModel> list = [];
    if (FirebaseService.isInitialized) {
      try {
        final docs = await FirebaseService.getGuidelinesOnce();
        list = docs.map((d) => GuidelineModel.fromMap({'id': d.id, ...d.data()})).toList();
      } catch (_) {}
    } else if (list.isEmpty) {
      try {
        final apiList = await ApiService().getGuidelines().timeout(
          const Duration(seconds: 3),
          onTimeout: () => <dynamic>[],
        );
        list = apiList.map((e) => GuidelineModel.fromMap(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    if (list.isEmpty) {
      list = GuidelinesData.defaultGuidelines;
    }
    if (mounted) setState(() {
      _guidelines = list;
      _loading = false;
    });
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
        title: Text('Hair Care Guidelines', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _guidelines.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.menu_book, size: 64, color: AppColors.textGrey),
                          const SizedBox(height: 16),
                          Text('No guidelines available', style: TextStyle(color: AppColors.textGrey)),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Expert tips for healthy hair', style: TextStyle(fontSize: 16, color: AppColors.textGrey)),
                          const SizedBox(height: 20),
                          ..._guidelines.map((g) => _GuidelineCard(guideline: g)),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
    );
  }
}

class _GuidelineCard extends StatelessWidget {
  final GuidelineModel guideline;

  const _GuidelineCard({required this.guideline});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.darkButton.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(guideline.category, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.darkButton)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(guideline.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          const SizedBox(height: 8),
          Text(guideline.content, style: TextStyle(fontSize: 14, color: AppColors.textGrey, height: 1.5)),
          if (guideline.tips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Tips:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textDark)),
            const SizedBox(height: 4),
            ...guideline.tips.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: Colors.teal),
                      const SizedBox(width: 8),
                      Expanded(child: Text(t, style: TextStyle(fontSize: 13, color: AppColors.textGrey))),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
