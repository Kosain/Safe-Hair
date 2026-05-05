import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/app_colors.dart';
import '../core/doctors_data.dart';
import '../core/nav_helper.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../providers/auth_provider.dart';

class DoctorListScreen extends StatefulWidget {
  const DoctorListScreen({super.key});

  @override
  State<DoctorListScreen> createState() => _DoctorListScreenState();
}

class _DoctorListScreenState extends State<DoctorListScreen> {
  List<dynamic> _doctors = [];
  bool _loading = true;
  int? _selectedIndex;
  int? _recommendedIndex;

  @override
  void initState() {
    super.initState();
    _checkProcessOrder();
    _loadDoctors();
  }

  Future<void> _checkProcessOrder() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null || !FirebaseService.isInitialized) return;
    final hasAnalysis = await FirebaseService.hasScalpAnalysis(userId);
    if (!mounted) return;
    if (!hasAnalysis) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tip: complete AI scalp analysis for better clinic recommendations.')),
      );
    }
  }

  void _showAnalysisRequiredDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('AI Scalp Analysis Required'),
        content: const Text(
          'Before booking a consultation, please complete AI scalp analysis first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.push('/scalp-analyzer');
            },
            child: const Text('Start Analysis'),
          ),
        ],
      ),
    );
  }

  void _bookSelectedDoctor() {
    final idx = _selectedIndex;
    if (_doctors.isEmpty || idx == null) return;
    final d = _doctors[idx] as Map<String, dynamic>;
    final name = (d['fullName'] ?? d['ownerName'] ?? d['displayName'] ?? d['name'] ?? 'Dr. Unknown').toString();
    final clinicName = (d['clinicName'] ?? d['clinic_name'] ?? d['displayName'] ?? d['name'] ?? 'Clinic').toString();
    final doctorId = d['id']?.toString() ?? d['userId']?.toString() ?? d['user_id']?.toString() ?? '';
    context.push('/appointment', extra: {'doctorId': doctorId, 'doctorName': name, 'clinicName': clinicName});
  }

  void _onDoctorTap(int index) {
    setState(() {
      if (_selectedIndex == index) {
        _selectedIndex = null;
      } else {
        _selectedIndex = index;
      }
    });
  }

  Future<void> _loadDoctors() async {
    try {
      final userId = context.read<AuthProvider>().userId;
      Map<String, dynamic>? latestAnalysis;
      if (userId != null && FirebaseService.isInitialized) {
        latestAnalysis = await FirebaseService.getLatestScalpAnalysisOnce(userId);
      }
      if (FirebaseService.isInitialized) {
        final list = await FirebaseService.getVerifiedDoctorsOnce();
        if (mounted) {
          final rows = list.isEmpty ? DoctorsData.defaultDoctors : list;
          setState(() {
            _doctors = rows;
            _recommendedIndex = _findBestClinicIndex(rows, latestAnalysis);
            _selectedIndex = null;
            _loading = false;
          });
        }
      } else {
        final list = await ApiService().getDoctors().timeout(
          const Duration(seconds: 5),
          onTimeout: () => <dynamic>[],
        );
        if (mounted) {
          final rows = list.isEmpty ? DoctorsData.defaultDoctors : list;
          setState(() {
            _doctors = rows;
            _recommendedIndex = _findBestClinicIndex(rows, latestAnalysis);
            _selectedIndex = null;
            _loading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() {
        _doctors = DoctorsData.defaultDoctors;
        _loading = false;
      });
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
        title: Text('Set Your Consultation Budget', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 130),
                  itemCount: _doctors.length,
                  itemBuilder: (_, i) {
                    final d = _doctors[i] as Map<String, dynamic>;
                    final name = (d['clinicName'] ?? d['clinic_name'] ?? d['fullName'] ?? d['ownerName'] ?? d['displayName'] ?? d['name'] ?? 'Clinic').toString();
                    final location = (d['clinicLocation'] ?? d['clinic_location'] ?? d['address'] ?? d['location'] ?? d['city'] ?? '').toString();
                    final specs = d['activeDoctorsData'] is List
                        ? (d['activeDoctorsData'] as List)
                            .map((e) => (e is Map ? e['domain'] : null)?.toString() ?? '')
                            .where((e) => e.isNotEmpty)
                            .toSet()
                            .join(', ')
                        : (d['specialization'] ?? d['specialization_name'] ?? '').toString();
                    final rating = (d['rating'] ?? 0).toString();
                    final feeRaw = d['consultation_fee'] ?? 0;
                    final teamFeeRaw = d['activeDoctorsData'] is List && (d['activeDoctorsData'] as List).isNotEmpty
                        ? (((d['activeDoctorsData'] as List).first is Map) ? ((d['activeDoctorsData'] as List).first as Map)['fee'] : null)
                        : null;
                    final fee = feeRaw is num
                        ? feeRaw.toInt()
                        : int.tryParse(feeRaw.toString()) ??
                            (teamFeeRaw is num ? teamFeeRaw.toInt() : int.tryParse(teamFeeRaw?.toString() ?? '')) ??
                            0;
                    return _DoctorCard(
                      name: name,
                      location: location,
                      subtitle: specs,
                      rating: double.tryParse(rating) ?? 0.0,
                      fee: fee,
                      profileImageUrl: (d['ownerProfileImageUrl'] ?? d['profileImageUrl'] ?? '').toString(),
                      profileImageBase64: (d['ownerProfileImageBase64'] ?? d['profileImageBase64'] ?? '').toString(),
                      recommended: _recommendedIndex == i,
                      selected: _selectedIndex == i,
                      dimmed: _selectedIndex != null && _selectedIndex != i,
                      onTap: () => _onDoctorTap(i),
                    );
                  },
                ),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  final String name;
  final String location;
  final String subtitle;
  final double rating;
  final int fee;
  final String profileImageUrl;
  final String profileImageBase64;
  final bool recommended;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  const _DoctorCard({
    required this.name,
    required this.location,
    required this.subtitle,
    required this.rating,
    required this.fee,
    required this.profileImageUrl,
    required this.profileImageBase64,
    required this.recommended,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = selected
        ? AppColors.primaryTeal
        : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06));
    final cardBg = isDark ? const Color(0xFF1B2230) : AppColors.cardBackground;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: dimmed ? 0.75 : 1,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 220),
        scale: selected ? 1.02 : 1.0,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor, width: selected ? 2.2 : 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: selected ? 0.14 : 0.06),
                  blurRadius: selected ? 18 : 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 72,
                        height: 72,
                        color: isDark ? const Color(0xFF2A3244) : Colors.white,
                        child: _buildProfileImage(),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            location,
                            style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : AppColors.textGrey),
                          ),
                          if (recommended) ...[
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Best Match',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.green),
                              ),
                            ),
                          ],
                          if (subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : AppColors.textGrey),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: List.generate(
                              5,
                              (i) => Icon(
                                Icons.star,
                                size: 18,
                                color: i < rating.round()
                                    ? Colors.amber
                                    : (isDark
                                        ? Colors.white24
                                        : AppColors.textGrey.withValues(alpha: 0.35)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryTeal,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, size: 16, color: Colors.white),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Column(
                  children: [
                    Text(
                      'PKR $fee',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                    Text(
                      'Recommended fare: PKR $fee',
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : AppColors.textGrey),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileImage() {
    if (profileImageUrl.trim().isNotEmpty) {
      return Image.network(
        profileImageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.medical_services_outlined, size: 36, color: AppColors.textGrey),
      );
    }
    if (profileImageBase64.trim().isNotEmpty) {
      try {
        final bytes = base64Decode(profileImageBase64);
        return Image.memory(bytes, fit: BoxFit.cover);
      } catch (_) {}
    }
    return const Icon(Icons.medical_services_outlined, size: 36, color: AppColors.textGrey);
  }
}

String _doctorLabel(dynamic row) {
  if (row is! Map) return 'selected doctor';
  final map = Map<String, dynamic>.from(row as Map);
  final name = (map['fullName'] ?? map['ownerName'] ?? map['displayName'] ?? map['name'] ?? 'Doctor').toString().trim();
  if (name.isNotEmpty) return name;
  return 'selected doctor';
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

int _findBestClinicIndex(List<dynamic> doctors, Map<String, dynamic>? analysis) {
  if (doctors.isEmpty) return 0;
  final baldRatio = _asDouble(analysis?['bald_ratio']);
  final severe = baldRatio >= 0.45;
  final moderate = baldRatio >= 0.25 && baldRatio < 0.45;

  double bestScore = -1e9;
  int bestIndex = 0;

  for (int i = 0; i < doctors.length; i++) {
    final d = doctors[i] is Map<String, dynamic> ? doctors[i] as Map<String, dynamic> : <String, dynamic>{};
    final fee = _asInt(d['consultation_fee']);
    final rating = _asDouble(d['rating']);
    final activeDoctors = _asInt(d['activeDoctorsCount']);
    final expYears = _asInt(d['experienceYears']);

    final domains = d['activeDoctorsData'] is List
        ? (d['activeDoctorsData'] as List)
            .map((e) => (e is Map ? e['domain'] : '').toString().toLowerCase())
            .where((e) => e.isNotEmpty)
            .join(' ')
        : '';
    final specialization = (d['specialization'] ?? '').toString().toLowerCase();
    final text = '$domains $specialization';

    double score = (rating * 20) + (expYears * 2.5) + (activeDoctors * 1.5);
    score -= (fee / 1500.0);

    if (severe) {
      if (text.contains('transplant') || text.contains('hair restoration')) score += 20;
      if (text.contains('dermat')) score += 8;
    } else if (moderate) {
      if (text.contains('dermat') || text.contains('hair')) score += 10;
    } else {
      score -= (fee / 2000.0);
    }

    if (score > bestScore) {
      bestScore = score;
      bestIndex = i;
    }
  }
  return bestIndex;
}
