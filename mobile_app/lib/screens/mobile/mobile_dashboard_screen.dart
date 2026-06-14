import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../core/safe_hair_colors.dart';
import '../../l10n/tr.dart';
import '../../providers/auth_provider.dart';
import '../../services/firebase_service.dart';
import '../../utils/dashboard_appointment_reminder.dart';

DateTime? _mobileHairScanDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

int _mobileCompareScanCreated(dynamic a, dynamic b) {
  final da = _mobileHairScanDate(a);
  final db = _mobileHairScanDate(b);
  if (da == null && db == null) return 0;
  if (da == null) return -1;
  if (db == null) return 1;
  return da.compareTo(db);
}

class MobileDashboardScreen extends StatefulWidget {
  const MobileDashboardScreen({super.key});

  @override
  State<MobileDashboardScreen> createState() => _MobileDashboardScreenState();
}

class _MobileDashboardScreenState extends State<MobileDashboardScreen> {
  String? _profileImageUrl;
  Uint8List? _profileImageBytes;
  String? _patientName;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadProfile();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null || !FirebaseService.isInitialized) return;

    final snap = await FirebaseService.getPatientDetails(userId);
    if (!mounted || snap == null) return;
    final data = snap.data();
    final url = data?['profileImageUrl']?.toString();
    final b64 = data?['profileImageBase64']?.toString();
    final patientName = data?['name']?.toString();

    Uint8List? decoded;
    if (b64 != null && b64.isNotEmpty) {
      try {
        decoded = base64Decode(b64);
      } catch (_) {}
    }

    setState(() {
      if (url != null && url.isNotEmpty) _profileImageUrl = url;
      if (decoded != null) _profileImageBytes = decoded;
      if (patientName != null && patientName.trim().isNotEmpty) _patientName = patientName.trim();
    });
  }

  Future<void> _onProfileAction(String value) async {
    if (value == 'settings') {
      context.push('/settings');
      return;
    }

    if (value == 'logout') {
      await context.read<AuthProvider>().signOut();
      if (!mounted) return;
      context.go('/role');
    }
  }

  void _showAiTips() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI Hair Care Tips'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• Oil your scalp 2–3 times per week.'),
            SizedBox(height: 6),
            Text('• Use mild sulfate-free shampoo.'),
            SizedBox(height: 6),
            Text('• Avoid excessive heat styling.'),
            SizedBox(height: 6),
            Text('• Stay hydrated and eat protein-rich foods.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final displayName = (_patientName != null && _patientName!.isNotEmpty)
        ? _patientName!
        : (auth.userName ?? 'User');
    final effectivePhotoUrl = (_profileImageUrl != null && _profileImageUrl!.isNotEmpty)
        ? _profileImageUrl
        : auth.userPhotoUrl;
    final effectivePhotoBytes = _profileImageBytes ?? auth.userPhotoBytes;

    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFFF4FAF6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: AppColors.textDark),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Color(0xFFDDF5E4),
                shape: BoxShape.circle,
              ),
              child: const Image(
                image: AssetImage('assets/logo.png'),
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Safe Hair',
              style: TextStyle(
                color: AppColors.textDark,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: PopupMenuButton<String>(
              tooltip: 'Profile actions',
              color: Colors.grey.shade100,
              onSelected: _onProfileAction,
              itemBuilder: (ctx) => [
                PopupMenuItem<String>(value: 'settings', child: Text(ctx.t('settings'), style: TextStyle(color: ctx.sh.textPrimary))),
                PopupMenuItem<String>(value: 'logout', child: Text(ctx.t('logout'), style: TextStyle(color: ctx.sh.textPrimary))),
              ],
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.darkButton,
                backgroundImage: (effectivePhotoUrl != null && effectivePhotoUrl.isNotEmpty)
                    ? NetworkImage(effectivePhotoUrl)
                    : (effectivePhotoBytes != null ? MemoryImage(effectivePhotoBytes) : null),
                child: ((effectivePhotoUrl == null || effectivePhotoUrl.isEmpty) && effectivePhotoBytes == null)
                    ? Text(
                        displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
      drawer: const _MobileDashboardDrawer(),
      body: Stack(
        children: [
          SafeArea(
            top: false,
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                child: _MobileDashboardContent(
                  userId: auth.userId,
                  onReminderAdd: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reminder action added.')),
                  ),
                  onAiTap: _showAiTips,
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _PatientFloatingBottomNav(currentRoute: '/dashboard'),
          ),
        ],
      ),
    );
  }
}

class _MobileDashboardContent extends StatelessWidget {
  const _MobileDashboardContent({
    required this.userId,
    required this.onReminderAdd,
    required this.onAiTap,
  });

  final String? userId;
  final VoidCallback onReminderAdd;
  final VoidCallback onAiTap;

  @override
  Widget build(BuildContext context) {
    if (userId != null && FirebaseService.isInitialized) {
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseService.patientDetailsStream(userId!),
        builder: (context, detailSnap) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseService.hairScansStream(userId!),
            builder: (context, scansSnap) {
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseService.getAppointments(userId!),
                builder: (context, apptSnap) {
                  final data = detailSnap.data?.data();
                  final strength = (data?['hairStrengthPct'] as num?)?.round();
                  final scalp = (data?['hairScalpHealthPct'] as num?)?.round();
                  final damage = (data?['hairDamageLevelPct'] as num?)?.round();
                  final fall = (data?['hairFallRiskPct'] as num?)?.round();
                  final hasData = strength != null && scalp != null && damage != null && fall != null;
                  final lastAt = _mobileHairScanDate(data?['hairLastScanAt']);
                  final lastLine = lastAt != null
                      ? 'Last scan: ${DateFormat('d MMM y').format(lastAt)}'
                      : 'Last scan: None';

                  final rawDocs = scansSnap.data?.docs ?? [];
                  final sorted = [...rawDocs]..sort(
                      (a, b) => _mobileCompareScanCreated(
                        a.data()['createdAt'],
                        b.data()['createdAt'],
                      ),
                    );

                  final apptLoading = apptSnap.connectionState == ConnectionState.waiting;
                  final appointmentReminder = nextUpcomingAppointmentSummary(apptSnap.data?.docs ?? const []);
                  final routineTip = data?['hairLatestRoutineTip']?.toString();

                  final metrics = [
                    _HairMetric(label: 'Hair Strength', value: hasData ? strength : null, color: const Color(0xFF59C6B0)),
                    _HairMetric(label: 'Scalp Health', value: hasData ? scalp : null, color: const Color(0xFFB76BCA)),
                    _HairMetric(label: 'Hair Damage Level', value: hasData ? damage : null, color: const Color(0xFF7B9ACD)),
                    _HairMetric(label: 'Hair Fall Risk', value: hasData ? fall : null, color: const Color(0xFFB7BD56)),
                  ];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HairHealthCard(
                        lastScanLine: lastLine,
                        metrics: metrics,
                        onAddTap: onReminderAdd,
                        appointmentReminder: appointmentReminder,
                        appointmentsLoading: apptLoading,
                      ),
                      const SizedBox(height: 12),
                      _AiSuggestionCard(onTap: onAiTap, latestTip: routineTip),
                      const SizedBox(height: 14),
                      _HairHealthProgressCard(scanDocs: sorted),
                    ],
                  );
                },
              );
            },
          );
        },
      );
    }

    const emptyMetrics = [
      _HairMetric(label: 'Hair Strength', value: null, color: Color(0xFF59C6B0)),
      _HairMetric(label: 'Scalp Health', value: null, color: Color(0xFFB76BCA)),
      _HairMetric(label: 'Hair Damage Level', value: null, color: Color(0xFF7B9ACD)),
      _HairMetric(label: 'Hair Fall Risk', value: null, color: Color(0xFFB7BD56)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HairHealthCard(
          lastScanLine: 'Last scan: None',
          metrics: emptyMetrics,
          onAddTap: onReminderAdd,
          appointmentReminder: null,
          appointmentsLoading: false,
          firebaseReady: false,
        ),
        const SizedBox(height: 12),
        _AiSuggestionCard(onTap: onAiTap, latestTip: null),
        const SizedBox(height: 14),
        const _HairHealthProgressCard(scanDocs: []),
      ],
    );
  }
}

class _MobileDashboardDrawer extends StatelessWidget {
  const _MobileDashboardDrawer();

  @override
  Widget build(BuildContext context) {
    final currentRoute = GoRouterState.of(context).matchedLocation;
    bool selected(String route) {
      if (route == '/chat-list') {
        return currentRoute == '/chat-list' || currentRoute.startsWith('/chat/');
      }
      return currentRoute == route || (route != '/dashboard' && currentRoute.startsWith(route));
    }

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(0xFFEFEFEF),
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: Image(image: AssetImage('assets/logo.png')),
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Safe Hair',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined, color: Colors.black),
              title: Text(context.t('nav_dashboard'), style: TextStyle(color: context.sh.textPrimary)),
              selected: selected('/dashboard'),
              selectedTileColor: const Color(0xFFF0F0F0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(context);
                context.go('/dashboard');
              },
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined, color: Colors.black),
              title: Text(context.t('nav_my_scans'), style: TextStyle(color: context.sh.textPrimary)),
              selected: selected('/my-scans'),
              selectedTileColor: const Color(0xFFF0F0F0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(context);
                context.go('/my-scans');
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined, color: Colors.black),
              title: Text(context.t('nav_my_appointments'), style: TextStyle(color: context.sh.textPrimary)),
              selected: selected('/my-appointments'),
              selectedTileColor: const Color(0xFFF0F0F0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(context);
                context.go('/my-appointments');
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined, color: Colors.black),
              title: Text(context.t('nav_my_reports'), style: TextStyle(color: context.sh.textPrimary)),
              selected: selected('/my-report'),
              selectedTileColor: const Color(0xFFF0F0F0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(context);
                context.go('/my-report');
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline, color: Colors.black),
              title: Text(context.t('nav_my_chats'), style: TextStyle(color: context.sh.textPrimary)),
              selected: selected('/chat-list'),
              selectedTileColor: const Color(0xFFF0F0F0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(context);
                context.go('/chat-list');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HairHealthCard extends StatelessWidget {
  const _HairHealthCard({
    required this.lastScanLine,
    required this.metrics,
    required this.onAddTap,
    this.appointmentReminder,
    this.appointmentsLoading = false,
    this.firebaseReady = true,
  });

  final String lastScanLine;
  final List<_HairMetric> metrics;
  final VoidCallback onAddTap;
  final AppointmentReminderLines? appointmentReminder;
  final bool appointmentsLoading;
  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF5A5A5A)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your hair health',
                      // Slightly reduced title size to match compact reference.
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.textDark),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lastScanLine,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF777777)),
                    ),
                  ],
                ),
              ),
              Material(
                color: const Color(0xFFE8E8E8),
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () {
                    int? valueFor(String label) {
                      for (final m in metrics) {
                        if (m.label == label) return m.value;
                      }
                      return null;
                    }
                    context.push(
                      '/hair-health-guide',
                      extra: {
                        'strength': valueFor('Hair Strength'),
                        'scalp': valueFor('Scalp Health'),
                        'damage': valueFor('Hair Damage Level'),
                        'fall': valueFor('Hair Fall Risk'),
                      },
                    );
                  },
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 32,
                    height: 32,
                    child: Icon(Icons.north_east_rounded, size: 18, color: Color(0xFF616161)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            itemCount: metrics.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              // Compact 2x2 cards (tighter + slightly shorter) like the reference.
              mainAxisSpacing: 7,
              crossAxisSpacing: 7,
              childAspectRatio: 1.88,
            ),
            itemBuilder: (context, index) => _MetricMiniCard(metric: metrics[index]),
          ),
          const SizedBox(height: 10),
          _ReminderCard(
            onAddTap: onAddTap,
            isEmbedded: true,
            reminder: appointmentReminder,
            appointmentsLoading: appointmentsLoading,
            firebaseReady: firebaseReady,
          ),
        ],
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.onAddTap,
    this.isEmbedded = false,
    this.reminder,
    this.appointmentsLoading = false,
    this.firebaseReady = true,
  });

  final VoidCallback onAddTap;
  final bool isEmbedded;
  final AppointmentReminderLines? reminder;
  final bool appointmentsLoading;
  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isEmbedded ? 16 : 20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: isEmbedded ? 6 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFF1F1F1),
            ),
            child: const Icon(Icons.notifications_none_rounded, size: 18, color: Colors.black),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Builder(
              builder: (context) {
                final String text;
                if (!firebaseReady) {
                  text = 'Sign in to see bookings here.';
                } else if (appointmentsLoading) {
                  text = 'Loading…';
                } else if (reminder != null) {
                  text = '${reminder!.whenLine}\n${reminder!.detailLine}';
                } else {
                  text = 'No upcoming appointment\nBook from My Appointments.';
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Reminder', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF666666), height: 1.2),
                    ),
                  ],
                );
              },
            ),
          ),
          InkWell(
            onTap: onAddTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: Color(0xFFE7EC74),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiSuggestionCard extends StatelessWidget {
  const _AiSuggestionCard({required this.onTap, this.latestTip});

  final VoidCallback onTap;
  final String? latestTip;

  @override
  Widget build(BuildContext context) {
    final tip = latestTip?.trim();
    final copy = (tip != null && tip.isNotEmpty)
        ? tip
        : 'Run a scalp analysis from My Scans to save your latest AI care recommendation here.';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF176),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                copy,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFF22232C),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_fix_high_rounded, size: 20, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricMiniCard extends StatelessWidget {
  const _MetricMiniCard({required this.metric});

  final _HairMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      // More compact metric card dimensions.
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // Metric names reduced to requested range (~13-14).
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4B4B4B),
              height: 1.15,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    metric.value != null ? '${metric.value}%' : '--%',
                    // Percentage capped <= 32 as requested.
                    style: const TextStyle(
                      fontSize: 31,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                // Smaller progress indicator to match compact card.
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  value: metric.value != null ? (metric.value!.clamp(0, 100)) / 100.0 : 0,
                  strokeWidth: 3.3,
                  backgroundColor: metric.color.withValues(alpha: 0.22),
                  valueColor: AlwaysStoppedAnimation(metric.color),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

double _mobileHairProgressChartWidth(int pointCount) {
  if (pointCount <= 1) return 600;
  return (pointCount * 56.0).clamp(600.0, 2400.0);
}

double _mobileHairProgressLabelInterval(int pointCount) {
  if (pointCount <= 8) return 1;
  if (pointCount <= 16) return 2;
  return (pointCount / 10).ceilToDouble().clamp(2, 12);
}

class _HairHealthProgressCard extends StatelessWidget {
  const _HairHealthProgressCard({required this.scanDocs});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> scanDocs;

  @override
  Widget build(BuildContext context) {
    if (scanDocs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.trending_up_rounded, size: 18, color: Color(0xFF2BAE9E)),
                SizedBox(width: 8),
                Text(
                  'Hair Health Progress',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 210,
              child: Center(
                child: Text(
                  'No scans yet',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final labels = <String>[];
    final spots = <FlSpot>[];
    for (var i = 0; i < scanDocs.length; i++) {
      final d = scanDocs[i].data();
      final avg = (d['averageScore'] as num?)?.toDouble() ?? 0.0;
      spots.add(FlSpot(i.toDouble(), avg.clamp(0, 100)));
      final created = _mobileHairScanDate(d['createdAt']);
      labels.add(created != null ? DateFormat('d MMM').format(created) : '#${i + 1}');
    }

    final maxX = (scanDocs.length - 1).toDouble();
    double minY = 100;
    double maxY = 0;
    for (final s in spots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }
    minY = (minY - 10).floorToDouble().clamp(0, 100);
    maxY = (maxY + 10).ceilToDouble().clamp(0, 100);
    if (maxY <= minY) {
      minY = 0;
      maxY = 100;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.trending_up_rounded, size: 18, color: Color(0xFF2BAE9E)),
              SizedBox(width: 8),
              Text(
                'Hair Health Progress',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 230,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _mobileHairProgressChartWidth(scanDocs.length),
                height: 230,
                child: LineChart(
                  LineChartData(
                    minY: minY,
                    maxY: maxY,
                    minX: 0,
                    maxX: maxX,
                    lineTouchData: LineTouchData(
                      enabled: true,
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            final index = spot.x.toInt();
                            final label = index >= 0 && index < labels.length ? labels[index] : '';
                            return LineTooltipItem(
                              '$label\n${spot.y.toInt()}',
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            );
                          }).toList();
                        },
                      ),
                    ),
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: 10,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: const Color(0xFFECEFF1),
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: const Border(
                        left: BorderSide(color: Color(0xFFE0E0E0)),
                        bottom: BorderSide(color: Color(0xFFE0E0E0)),
                        top: BorderSide.none,
                        right: BorderSide.none,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 10,
                          reservedSize: 30,
                          getTitlesWidget: (value, meta) => Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10, color: Color(0xFF7A7A7A)),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 38,
                          interval: _mobileHairProgressLabelInterval(scanDocs.length),
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= labels.length) return const SizedBox.shrink();
                            return Transform.rotate(
                              angle: -0.4,
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  labels[index],
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF7A7A7A)),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: const Color(0xFF2BAE9E),
                        barWidth: 3,
                        isStrokeCapRound: true,
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              const Color(0xFF2BAE9E).withValues(alpha: 0.22),
                              const Color(0xFF2BAE9E).withValues(alpha: 0.02),
                            ],
                          ),
                        ),
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                            radius: 3.6,
                            color: const Color(0xFF2BAE9E),
                            strokeColor: Colors.white,
                            strokeWidth: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HairMetric {
  const _HairMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int? value;
  final Color color;
}

class _PatientFloatingBottomNav extends StatelessWidget {
  const _PatientFloatingBottomNav({required this.currentRoute});

  final String currentRoute;

  @override
  Widget build(BuildContext context) {
    bool selected(String route) {
      if (route == '/chat-list') {
        return currentRoute == '/chat-list' || currentRoute.startsWith('/chat/');
      }
      return currentRoute == route || (route != '/dashboard' && currentRoute.startsWith(route));
    }

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        height: 74,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _BottomNavItem(
              icon: Icons.home_rounded,
              selected: selected('/dashboard'),
              onTap: () => context.go('/dashboard'),
            ),
            _BottomNavItem(
              icon: Icons.crop_free_rounded,
              selected: selected('/my-scans'),
              onTap: () => context.go('/my-scans'),
            ),
            _BottomNavItem(
              icon: Icons.calendar_month_outlined,
              selected: selected('/my-appointments'),
              onTap: () => context.go('/my-appointments'),
            ),
            _BottomNavItem(
              icon: Icons.description_outlined,
              selected: selected('/my-report'),
              onTap: () => context.go('/my-report'),
            ),
            if (!kIsWeb)
              _BottomNavItem(
                icon: Icons.chat_outlined,
                selected: selected('/chat-list'),
                onTap: () => context.go('/chat-list'),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 50,
        height: 48,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF151515) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 24,
          color: selected ? Colors.white : Colors.grey.shade600,
        ),
      ),
    );
  }
}
