import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
import '../widgets/patient_web_scaffold.dart';

DateTime? _hairScanDateFromFirestore(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

int _compareHairScanCreated(dynamic a, dynamic b) {
  final da = _hairScanDateFromFirestore(a);
  final db = _hairScanDateFromFirestore(b);
  if (da == null && db == null) return 0;
  if (da == null) return -1;
  if (db == null) return 1;
  return da.compareTo(db);
}

class PatientDashboardScreen extends StatefulWidget {
  const PatientDashboardScreen({super.key});

  @override
  State<PatientDashboardScreen> createState() => _PatientDashboardScreenState();
}

class _PatientDashboardScreenState extends State<PatientDashboardScreen> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = GoRouterState.of(context).matchedLocation;
    final uid = context.watch<AuthProvider>().userId;
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final bottomPad = isWide ? 0.0 : 88.0;

    Widget body;
    if (uid != null && FirebaseService.isInitialized) {
      body = StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseService.patientDetailsStream(uid),
        builder: (context, detailSnap) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseService.hairScansStream(uid),
            builder: (context, scansSnap) {
              final data = detailSnap.data?.data();
              final strength = (data?['hairStrengthPct'] as num?)?.round();
              final scalp = (data?['hairScalpHealthPct'] as num?)?.round();
              final damage = (data?['hairDamageLevelPct'] as num?)?.round();
              final fall = (data?['hairFallRiskPct'] as num?)?.round();
              final hasData = strength != null && scalp != null && damage != null && fall != null;
              final lastAt = _hairScanDateFromFirestore(data?['hairLastScanAt']);
              final lastLine = lastAt != null
                  ? 'Last scan: ${DateFormat('d MMM y').format(lastAt)}'
                  : 'Last scan: None';

              final rawDocs = scansSnap.data?.docs ?? [];
              final sorted = [...rawDocs]..sort(
                  (a, b) => _compareHairScanCreated(
                    a.data()['createdAt'],
                    b.data()['createdAt'],
                  ),
                );

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    children: [
                      _MetricsCard(
                        lastScanLine: lastLine,
                        hasMetrics: hasData,
                        strength: strength,
                        scalp: scalp,
                        damage: damage,
                        fall: fall,
                      ),
                      const SizedBox(height: 16),
                      const IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _ReminderCard()),
                            SizedBox(width: 14),
                            Expanded(child: _RoutineCard()),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ChartCard(scanDocs: sorted),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } else {
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              const _MetricsCard(
                lastScanLine: 'Last scan: None',
                hasMetrics: false,
                strength: null,
                scalp: null,
                damage: null,
                fall: null,
              ),
              const SizedBox(height: 16),
              const IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _ReminderCard()),
                    SizedBox(width: 14),
                    Expanded(child: _RoutineCard()),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const _ChartCard(scanDocs: []),
            ],
          ),
        ),
      );
    }

    return PatientWebScaffold(
      currentRoute: route,
      showScrollbar: true,
      bodyScrollController: _scrollController,
      extraScrollBottomPadding: bottomPad,
      body: body,
    );
  }
}

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({
    required this.lastScanLine,
    required this.hasMetrics,
    required this.strength,
    required this.scalp,
    required this.damage,
    required this.fall,
  });

  final String lastScanLine;
  final bool hasMetrics;
  final int? strength;
  final int? scalp;
  final int? damage;
  final int? fall;

  static const _labels = [
    'Hair Strength',
    'Scalp Health',
    'Hair Damage Level',
    'Hair Fall Risk',
  ];

  @override
  Widget build(BuildContext context) {
    final values = [strength, scalp, damage, fall];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your hair health',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.black),
          ),
          const SizedBox(height: 4),
          Text(lastScanLine, style: const TextStyle(color: Color(0xFF5D5D5D))),
          const SizedBox(height: 16),
          Row(
            children: List.generate(4, (i) {
              final label = _labels[i];
              final v = hasMetrics ? values[i] : null;
              return Expanded(child: _MetricTile(label: label, value: v));
            }),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) {
    final ring = _ringColor(label);
    final progressValue = value != null ? (value!.clamp(0, 100)) / 100.0 : 0.0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                value != null ? '$value%' : '--%',
                style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w700, height: 0.95),
              ),
              const Spacer(),
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  value: progressValue,
                  strokeWidth: 4,
                  backgroundColor: ring.withValues(alpha: 0.22),
                  valueColor: AlwaysStoppedAnimation(ring),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _ringColor(String metricLabel) {
    switch (metricLabel) {
      case 'Hair Strength':
        return const Color(0xFF59C6B0);
      case 'Scalp Health':
        return const Color(0xFFB76BCA);
      case 'Hair Damage Level':
        return const Color(0xFF7B9ACD);
      case 'Hair Fall Risk':
        return const Color(0xFFB7BD56);
      default:
        return const Color(0xFF2E2E2E);
    }
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9F0EB)),
        boxShadow: const [
          BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Add reminder coming soon')),
                  );
                },
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_rounded, color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Reminder', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('Today 10 AM', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Apply Hair Organic Oil', style: TextStyle(color: Color(0xFF5F5F5F))),
        ],
      ),
    );
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF176),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0E665)),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('AI analysis coming soon')),
                  );
                },
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('AI Daily Routine', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'AI will analyse your hair and make an auto daily routine',
            style: TextStyle(height: 1.25, color: Color(0xFF1E1E1E), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.scanDocs});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> scanDocs;

  @override
  Widget build(BuildContext context) {
    if (scanDocs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: const [
            BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hair Health Progress', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            SizedBox(
              height: 260,
              child: Center(
                child: Text(
                  'No scans yet',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Hair Strength Over Time', style: TextStyle(fontSize: 12, color: Color(0xFF626262))),
          ],
        ),
      );
    }

    final labels = <String>[];
    final spots = <FlSpot>[];
    for (var i = 0; i < scanDocs.length; i++) {
      final d = scanDocs[i].data();
      final avg = (d['averageScore'] as num?)?.toDouble();
      final y = avg ?? 0.0;
      spots.add(FlSpot(i.toDouble(), y.clamp(0, 100)));
      final created = _hairScanDateFromFirestore(d['createdAt']);
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [
          BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Hair Health Progress', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          SizedBox(
            height: 260,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: maxX,
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: 10,
                  getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFEDEDED)),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: const Border(
                    left: BorderSide(color: Color(0xFFD9D9D9)),
                    bottom: BorderSide(color: Color(0xFFD9D9D9)),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: 10,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6A6A6A)),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(labels[i], style: const TextStyle(fontSize: 11, color: Color(0xFF6A6A6A))),
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
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                        radius: 3.8,
                        color: const Color(0xFF2BAE9E),
                        strokeColor: Colors.white,
                        strokeWidth: 1.3,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF2BAE9E).withValues(alpha: 0.20),
                          const Color(0xFF2BAE9E).withValues(alpha: 0.03),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Hair Strength Over Time', style: TextStyle(fontSize: 12, color: Color(0xFF626262))),
        ],
      ),
    );
  }
}
