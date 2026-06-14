import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/safe_hair_colors.dart';
import '../l10n/tr.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
import '../utils/dashboard_appointment_reminder.dart';
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
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseService.getAppointments(uid),
                builder: (context, apptSnap) {
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

                  final apptLoading = apptSnap.connectionState == ConnectionState.waiting;
                  final reminder = nextUpcomingAppointmentSummary(apptSnap.data?.docs ?? const []);

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
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _ReminderCard(
                                    reminder: reminder,
                                    appointmentsLoading: apptLoading,
                                    firebaseReady: true,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: const _RoutineCard(),
                                ),
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
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Expanded(
                      child: _ReminderCard(
                        reminder: null,
                        appointmentsLoading: false,
                        firebaseReady: false,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(child: _RoutineCard()),
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
    final sh = context.sh;
    final values = [strength, scalp, damage, fall];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: sh.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: sh.border),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your hair health',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: sh.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(lastScanLine, style: TextStyle(color: sh.textSecondary)),
                  ],
                ),
              ),
              Material(
                color: sh.sidebarSelectedBg,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () {
                    context.push(
                      '/hair-health-guide',
                      extra: {
                        'strength': hasMetrics ? strength : null,
                        'scalp': hasMetrics ? scalp : null,
                        'damage': hasMetrics ? damage : null,
                        'fall': hasMetrics ? fall : null,
                      },
                    );
                  },
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(Icons.north_east_rounded, size: 20, color: sh.textSecondary),
                  ),
                ),
              ),
            ],
          ),
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
    final sh = context.sh;
    final ring = _ringColor(label);
    final progressValue = value != null ? (value!.clamp(0, 100)) / 100.0 : 0.0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: sh.sidebarSelectedBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: sh.border),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: sh.textPrimary)),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                value != null ? '$value%' : '--%',
                style: TextStyle(fontSize: 42, fontWeight: FontWeight.w700, height: 0.95, color: sh.textPrimary),
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
  const _ReminderCard({
    this.reminder,
    this.appointmentsLoading = false,
    this.firebaseReady = true,
  });

  final AppointmentReminderLines? reminder;
  final bool appointmentsLoading;
  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    final String line1;
    final String line2;
    if (!firebaseReady) {
      line1 = 'Sign in to load data';
      line2 = 'Your appointment reminders appear here after you sign in.';
    } else if (appointmentsLoading) {
      line1 = 'Loading…';
      line2 = 'Fetching your bookings.';
    } else if (reminder != null) {
      line1 = reminder!.whenLine;
      line2 = reminder!.detailLine;
    } else {
      line1 = 'No upcoming appointment';
      line2 = 'Book a consultation from My Appointments.';
    }

    final sh = context.sh;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: sh.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: sh.border),
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
                  if (firebaseReady) context.push('/my-appointments');
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
              Expanded(
                child: Text(context.t('reminder'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: sh.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(line1, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: sh.textPrimary)),
          const SizedBox(height: 4),
          Text(line2, style: TextStyle(color: sh.textSecondary, height: 1.25)),
        ],
      ),
    );
  }
}

class _RoutineCard extends StatefulWidget {
  const _RoutineCard();

  @override
  State<_RoutineCard> createState() => _RoutineCardState();
}

class _RoutineCardState extends State<_RoutineCard> {
  static const _tips = [
    'Massage your scalp for 5 minutes daily to boost circulation.',
    'Use a silk or satin pillowcase to reduce friction and hair breakage.',
    'Wash hair with lukewarm water; hot water strips natural oils.',
    'Apply conditioner mainly to the ends, not the scalp.',
    'Trim split ends every 6–8 weeks to prevent further damage.',
    'Avoid tight hairstyles that pull on the hairline (traction alopecia).',
    'Eat protein-rich foods like eggs, fish, and beans for stronger hair.',
    'Use a wide-tooth comb on wet hair to minimize breakage.',
    'Limit heat styling; always use a heat protectant spray.',
    'Stay hydrated – drink enough water to keep your scalp healthy.',
    'Incorporate iron-rich foods (spinach, lentils) to prevent shedding.',
    'Use a gentle, sulfate-free shampoo to avoid scalp irritation.',
    "Don't rub your hair vigorously with a towel – pat dry instead.",
    'Take a break from chemical treatments like perms or relaxers.',
    'Protect your hair from the sun with a hat or UV-protectant spray.',
    'Try a weekly hot oil treatment (coconut, argan, or jojoba oil).',
    "Avoid brushing hair when it's wet – use a detangling spray first.",
    'Manage stress – high stress levels can trigger telogen effluvium.',
    'Take biotin or multivitamin supplements after consulting a doctor.',
    'Do a scalp scrub once a month to remove buildup and dead skin.',
    'Alternate between different shampoos to prevent product buildup.',
    'Use a leave-in conditioner for added moisture and protection.',
    'Avoid over-washing – 2–3 times a week is usually enough.',
    'Sleep with your hair in a loose braid or bun to prevent tangles.',
    'Apply a few drops of rosemary oil to the scalp to promote growth.',
    'Avoid smoking – it reduces blood flow to hair follicles.',
    'Use a humidifier in dry climates to keep scalp hydrated.',
    "Don't share combs, brushes, or hats to prevent fungal infections.",
    'Rinse hair with cool water after conditioning to seal cuticles.',
    'Take a break from hair dryers and let your hair air-dry sometimes.',
    'Use a boar bristle brush to distribute natural oils evenly.',
    'Avoid hairstyles that require heavy gels or alcohol-based products.',
    'Eat foods rich in omega-3 fatty acids (salmon, walnuts, flaxseeds).',
    'Check your thyroid and iron levels if you experience sudden hair loss.',
    'Use a microfiber towel to reduce friction and frizz.',
    "Don't scratch your scalp – treat dandruff with medicated shampoo.",
    'Take a collagen supplement to support hair structure.',
    'Avoid frequent dyeing – space out color treatments by 6–8 weeks.',
    'Use a satin scrunchie instead of elastic bands to prevent breakage.',
    'Get enough sleep – growth hormone is released during deep sleep.',
    'Apply aloe vera gel to soothe an irritated scalp.',
    "Don't ignore sudden patchy hair loss – see a dermatologist.",
    'Use a shower filter to remove chlorine and heavy metals.',
    'Avoid high-sugar diets – they can trigger inflammation and shedding.',
    'Try inversion method (bending over and massaging scalp for 4 minutes).',
    'Use a hair serum with niacinamide to strengthen follicles.',
    "Don't overuse dry shampoo – it can clog pores and cause buildup.",
    'Take a hair growth supplement containing saw palmetto (for men) or iron (for women).',
    'Avoid sleeping with wet hair – it can lead to fungal growth.',
    'Be patient – hair grows about 0.5 inches per month; results take time.',
  ];

  late String _currentTip;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _currentTip = _tips[_random.nextInt(_tips.length)];
  }

  void _showNewTip() {
    if (_tips.length <= 1) return;
    var next = _tips[_random.nextInt(_tips.length)];
    while (next == _currentTip) {
      next = _tips[_random.nextInt(_tips.length)];
    }
    setState(() => _currentTip = next);
  }

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
              Material(
                color: Colors.black,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _showNewTip,
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Quick Tips',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.black),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _currentTip,
            style: const TextStyle(
              fontSize: 15,
              height: 1.35,
              color: Color(0xFF1E1E1E),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

double _hairProgressChartWidth(int pointCount) {
  if (pointCount <= 1) return 600;
  return (pointCount * 56.0).clamp(600.0, 2400.0);
}

double _hairProgressLabelInterval(int pointCount) {
  if (pointCount <= 8) return 1;
  if (pointCount <= 16) return 2;
  return (pointCount / 10).ceilToDouble().clamp(2, 12);
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.scanDocs});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> scanDocs;

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    if (scanDocs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: sh.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: sh.border),
          boxShadow: const [
            BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.t('hair_health_progress'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: context.sh.textPrimary)),
            const SizedBox(height: 14),
            SizedBox(
              height: 260,
              child: Center(
                child: Text(
                  'No scans yet',
                  style: TextStyle(fontSize: 16, color: sh.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(context.t('hair_strength_over_time'), style: TextStyle(fontSize: 12, color: context.sh.textSecondary)),
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
        color: sh.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: sh.border),
        boxShadow: const [
          BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('hair_health_progress'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: sh.textPrimary)),
          const SizedBox(height: 14),
          SizedBox(
            height: 280,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _hairProgressChartWidth(scanDocs.length),
                height: 280,
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: maxX,
                    minY: minY,
                    maxY: maxY,
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: 10,
                      getDrawingHorizontalLine: (_) => FlLine(color: sh.border),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border(
                        left: BorderSide(color: sh.border),
                        bottom: BorderSide(color: sh.border),
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
                            style: TextStyle(fontSize: 11, color: sh.textSecondary),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          interval: _hairProgressLabelInterval(scanDocs.length),
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                            return Transform.rotate(
                              angle: -0.4,
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  labels[i],
                                  style: TextStyle(fontSize: 10, color: sh.textSecondary),
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
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                            radius: 3.8,
                            color: const Color(0xFF2BAE9E),
                            strokeColor: sh.card,
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
            ),
          ),
          const SizedBox(height: 8),
          Text(context.t('hair_strength_over_time'), style: TextStyle(fontSize: 12, color: sh.textSecondary)),
        ],
      ),
    );
  }
}
