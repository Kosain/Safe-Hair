import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static const _metrics = <_Metric>[
    _Metric('Hair Strength', 72),
    _Metric('Scalp Health', 60),
    _Metric('Hair Damage Level', 45),
    _Metric('Hair Fall Risk', 80),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = auth.userName ?? 'User';
    final photoUrl = auth.userPhotoUrl;
    final photoBytes = auth.userPhotoBytes;
    final path = GoRouterState.of(context).matchedLocation;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    final content = Container(
      color: const Color(0xFFF5F5F5),
      child: Column(
        children: [
          _TopBar(
            showMenu: !isDesktop,
            name: name,
            photoUrl: photoUrl,
            photoBytes: photoBytes,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(isDesktop ? 24 : 16, 20, isDesktop ? 24 : 16, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    children: [
                      _MetricSection(metrics: _metrics, isDesktop: isDesktop),
                      const SizedBox(height: 16),
                      if (isDesktop)
                        const Row(
                          children: [
                            Expanded(child: _ReminderCard()),
                            SizedBox(width: 14),
                            Expanded(child: _RoutineCard()),
                          ],
                        )
                      else ...[
                        const _ReminderCard(),
                        const SizedBox(height: 14),
                        const _RoutineCard(),
                      ],
                      const SizedBox(height: 16),
                      const _ChartCard(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (!isDesktop) {
      return Scaffold(
        drawer: _Sidebar(path: path, inDrawer: true),
        body: content,
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(path: path, inDrawer: false),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.showMenu,
    required this.name,
    required this.photoUrl,
    required this.photoBytes,
  });

  final bool showMenu;
  final String name;
  final String? photoUrl;
  final Uint8List? photoBytes;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8E8E8))),
      ),
      child: Row(
        children: [
          if (showMenu)
            Builder(
              builder: (ctx) => IconButton(
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                icon: const Icon(Icons.menu_rounded),
              ),
            ),
          Text('Dashboard', style: TextStyle(fontSize: showMenu ? 24 : 26, fontWeight: FontWeight.w700)),
          const Spacer(),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'settings') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings will be available soon.')),
                );
                return;
              }
              await auth.signOut();
              if (context.mounted) context.go('/role');
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(value: 'settings', child: Text('Settings')),
              PopupMenuItem<String>(value: 'logout', child: Text('Logout')),
            ],
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.black,
              backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty)
                  ? NetworkImage(photoUrl!)
                  : (photoBytes != null ? MemoryImage(photoBytes!) : null),
              child: ((photoUrl == null || photoUrl!.isEmpty) && photoBytes == null)
                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white))
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.path, required this.inDrawer});
  final String path;
  final bool inDrawer;

  @override
  Widget build(BuildContext context) {
    final nav = [
      ('Dashboard', Icons.dashboard_outlined, '/dashboard'),
      ('My Scans', Icons.document_scanner_outlined, '/scalp-analyzer'),
      ('Consultations', Icons.people_outline, '/doctors'),
      ('Profile', Icons.person_outline, '/patient-details'),
      ('Settings', Icons.settings_outlined, ''),
    ];

    Widget body = Container(
      color: const Color(0xFFF8F8F8),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Row(
                children: [
                  CircleAvatar(radius: 18, backgroundColor: Color(0xFFEFEFEF), child: Image(image: AssetImage('assets/logo.png'))),
                  SizedBox(width: 10),
                  Text('Safe Hair', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 10),
            ...nav.map((item) {
              final selected = item.$3.isNotEmpty && (path == item.$3 || path.startsWith(item.$3));
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                child: Material(
                  color: selected ? const Color(0xFFEAEAEA) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (item.$3.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings will be available soon.')));
                      } else {
                        context.go(item.$3);
                      }
                      if (inDrawer) Navigator.of(context).pop();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Row(children: [Icon(item.$2), const SizedBox(width: 12), Text(item.$1)]),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
    return inDrawer ? Drawer(width: 264, child: body) : SizedBox(width: 264, child: body);
  }
}

class _MetricSection extends StatelessWidget {
  const _MetricSection({required this.metrics, required this.isDesktop});
  final List<_Metric> metrics;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE9E9E9))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your hair health', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Last scan: Today', style: TextStyle(color: Color(0xFF5D5D5D))),
        const SizedBox(height: 16),
        isDesktop
            ? Row(children: metrics.map((m) => Expanded(child: _MetricCircle(metric: m))).toList())
            : Wrap(spacing: 12, runSpacing: 12, children: metrics.map((m) => SizedBox(width: 280, child: _MetricCircle(metric: m))).toList()),
      ]),
    );
  }
}

class _MetricCircle extends StatelessWidget {
  const _MetricCircle({required this.metric});
  final _Metric metric;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE7E7E7))),
      child: Column(children: [
        SizedBox(
          width: 90,
          height: 90,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(value: metric.value / 100, strokeWidth: 9, backgroundColor: const Color(0xFFE5E5E5), valueColor: const AlwaysStoppedAnimation(Colors.black)),
            Text('${metric.value}%', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 10),
        Text(metric.label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE7E7E7))),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Reminder', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        SizedBox(height: 10),
        Text('Today 10 AM', style: TextStyle(fontSize: 16)),
        SizedBox(height: 4),
        Text('Apply Hair Organic Oil', style: TextStyle(color: Color(0xFF5F5F5F))),
      ]),
    );
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFFF2F2F2), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE3E3E3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('AI Daily Routine', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        const Text('AI will analyze your hair and make an auto daily routine', style: TextStyle(height: 1.35, color: Color(0xFF505050))),
        const SizedBox(height: 16),
        FilledButton(onPressed: () {}, style: FilledButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white), child: const Text('Generate Routine')),
      ]),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard();
  @override
  Widget build(BuildContext context) {
    const labels = ['Week 1', 'Week 2', 'Week 3', 'Week 4', 'Week 5'];
    const spots = [FlSpot(0, 50), FlSpot(1, 60), FlSpot(2, 70), FlSpot(3, 80), FlSpot(4, 72)];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE7E7E7))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Hair Health Progress', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        SizedBox(
          height: 260,
          child: LineChart(LineChartData(
            minX: 0, maxX: 4, minY: 40, maxY: 100,
            gridData: FlGridData(drawVerticalLine: false, horizontalInterval: 10, getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFEDEDED))),
            borderData: FlBorderData(show: true, border: const Border(left: BorderSide(color: Color(0xFFD9D9D9)), bottom: BorderSide(color: Color(0xFFD9D9D9)))),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 26, interval: 10, getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 11, color: Color(0xFF6A6A6A))))),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 1, getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 8), child: Text(labels[i], style: const TextStyle(fontSize: 11, color: Color(0xFF6A6A6A))));
              })),
            ),
            lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: Colors.black, barWidth: 3, dotData: const FlDotData(show: true), belowBarData: BarAreaData(show: true, color: const Color(0x14000000)))],
          )),
        ),
        const SizedBox(height: 8),
        const Text('Hair Strength Over Time', style: TextStyle(fontSize: 12, color: Color(0xFF626262))),
      ]),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value);
  final String label;
  final int value;
}
import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const double _sidebarWidth = 264;

  Map<String, dynamic>? _latestAnalysis;
  Map<String, dynamic>? _nextAppointment;
  String? _profileImageUrl;
  Uint8List? _profileImageBytes;
  String? _patientName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_latestAnalysis == null && _nextAppointment == null) _listenToData();
  }

  void _listenToData() {
    final userId = context.read<AuthProvider>().userId;
    if (FirebaseService.isInitialized) {
      final current = FirebaseService.currentUser;
      if (current?.photoURL != null && current!.photoURL!.isNotEmpty) {
        _profileImageUrl = current.photoURL;
      }
      if (current?.displayName != null && current!.displayName!.trim().isNotEmpty) {
        _patientName = current.displayName!.trim();
      }
    }

    if (userId == null || !FirebaseService.isInitialized) return;

    FirebaseService.getPatientDetails(userId).then((snap) {
      if (!mounted || snap == null) return;
      final data = snap.data();
      final url = data?['profileImageUrl']?.toString();
      final b64 = data?['profileImageBase64']?.toString();
      final name = data?['name']?.toString();
      setState(() {
        if (url != null && url.isNotEmpty) _profileImageUrl = url;
        if (b64 != null && b64.isNotEmpty) {
          try {
            _profileImageBytes = base64Decode(b64);
          } catch (_) {}
        }
        if (name != null && name.trim().isNotEmpty) _patientName = name.trim();
      });
    });

    FirebaseService.getScalpAnalyses(userId).listen((snap) {
      if (!mounted || snap.docs.isEmpty) return;
      final rows = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList()
        ..sort((a, b) => (b['createdAt'] ?? '').toString().compareTo((a['createdAt'] ?? '').toString()));
      if (rows.isNotEmpty) {
        setState(() => _latestAnalysis = rows.first);
      }
    });

    FirebaseService.getAppointments(userId).listen((snap) {
      if (!mounted || snap.docs.isEmpty) return;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['status'] == 'confirmed') {
          setState(() => _nextAppointment = {'id': doc.id, ...data});
          break;
        }
      }
    });
  }

  Future<void> _onProfileAction(String value, AuthProvider auth) async {
    if (value == 'settings') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings will be available soon.')),
      );
      return;
    }
    if (value == 'logout') {
      await auth.signOut();
      if (!mounted) return;
      context.go('/role');
    }
  }

  List<_MetricData> _metrics() {
    int read(dynamic v, int fallback) {
      if (v is num) return v.toInt().clamp(0, 100);
      if (v is String) return (int.tryParse(v) ?? fallback).clamp(0, 100);
      return fallback;
    }

    final m = _latestAnalysis;
    return [
      _MetricData('Hair Strength', read(m?['hairStrength'] ?? m?['hair_strength'], 72)),
      _MetricData('Scalp Health', read(m?['scalpHealth'] ?? m?['scalp_health'], 60)),
      _MetricData('Hair Damage Level', read(m?['hairDamageLevel'] ?? m?['hair_damage_level'], 45)),
      _MetricData('Hair Fall Risk', read(m?['hairFallRisk'] ?? m?['hair_fall_risk'], 80)),
    ];
  }

  Widget _sidebar(String path, bool mobileDrawer) {
    bool selected(String route) => path == route || (route != '/dashboard' && path.startsWith(route));

    final items = [
      _SidebarItem('Dashboard', Icons.dashboard_outlined, '/dashboard'),
      _SidebarItem('My Scans', Icons.document_scanner_outlined, '/scalp-analyzer'),
      _SidebarItem('Consultations', Icons.people_outline, '/doctors'),
      _SidebarItem('Profile', Icons.person_outline, '/patient-details'),
      _SidebarItem('Settings', Icons.settings_outlined, ''),
    ];

    final body = Container(
      color: const Color(0xFFF8F8F8),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: Color(0xFFEFEFEF), shape: BoxShape.circle),
                    child: const Image(image: AssetImage('assets/logo.png')),
                  ),
                  const SizedBox(width: 10),
                  const Text('Safe Hair', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE4E4E4)),
            const SizedBox(height: 10),
            ...items.map((item) {
              final isSelected = item.route.isNotEmpty && selected(item.route);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                child: Material(
                  color: isSelected ? const Color(0xFFEAEAEA) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (item.label == 'Settings') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Settings will be available soon.')),
                        );
                      } else {
                        context.go(item.route);
                      }
                      if (mobileDrawer) Navigator.of(context).pop();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Row(
                        children: [
                          Icon(item.icon, size: 22, color: Colors.black87),
                          const SizedBox(width: 12),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.black,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );

    if (mobileDrawer) return Drawer(width: _sidebarWidth, child: body);
    return SizedBox(width: _sidebarWidth, child: body);
  }

  Widget _topBar({
    required bool showMenu,
    required String name,
    required String? photoUrl,
    required Uint8List? photoBytes,
    required AuthProvider auth,
  }) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8E8E8))),
      ),
      child: Row(
        children: [
          if (showMenu)
            Builder(
              builder: (ctx) => IconButton(
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                icon: const Icon(Icons.menu_rounded),
              ),
            ),
          Text('Dashboard', style: TextStyle(fontSize: showMenu ? 24 : 26, fontWeight: FontWeight.w700)),
          const Spacer(),
          PopupMenuButton<String>(
            onSelected: (v) => _onProfileAction(v, auth),
            itemBuilder: (_) => const [
              PopupMenuItem<String>(value: 'settings', child: Text('Settings')),
              PopupMenuItem<String>(value: 'logout', child: Text('Logout')),
            ],
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.black,
              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                  ? NetworkImage(photoUrl)
                  : (photoBytes != null ? MemoryImage(photoBytes) : null),
              child: ((photoUrl == null || photoUrl.isEmpty) && photoBytes == null)
                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white))
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricSection(bool desktop) {
    final metrics = _metrics();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9E9E9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your hair health', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Last scan: ${_latestAnalysis == null ? 'Today' : _formatDate(_latestAnalysis!['createdAt'])}',
            style: const TextStyle(fontSize: 14, color: Color(0xFF5D5D5D)),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (_, c) {
              if (desktop && c.maxWidth > 850) {
                return Row(
                  children: metrics
                      .map((e) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _MetricCircle(e))))
                      .toList(),
                );
              }
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: metrics
                    .map((e) => SizedBox(
                          width: c.maxWidth < 540 ? c.maxWidth : (c.maxWidth - 14) / 2,
                          child: _MetricCircle(e),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _reminderCard() {
    final title = _nextAppointment != null ? '${_nextAppointment!['date']} ${_nextAppointment!['timeSlot'] ?? ''}'.trim() : 'Today 10 AM';
    final desc = _nextAppointment != null
        ? 'Consultation with ${_nextAppointment!['doctorName'] ?? 'doctor'}'
        : 'Apply Hair Organic Oil';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7E7E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Reminder', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          Text(desc, style: const TextStyle(fontSize: 14, color: Color(0xFF5F5F5F))),
        ],
      ),
    );
  }

  Widget _routineCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E3E3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('AI Daily Routine', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text(
            'AI will analyze your hair and make an auto daily routine',
            style: TextStyle(fontSize: 14, height: 1.35, color: Color(0xFF505050)),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Routine generator will be available soon.')),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Generate Routine'),
          ),
        ],
      ),
    );
  }

  Widget _chartCard() {
    const labels = ['Week 1', 'Week 2', 'Week 3', 'Week 4', 'Week 5'];
    const spots = [FlSpot(0, 50), FlSpot(1, 60), FlSpot(2, 70), FlSpot(3, 80), FlSpot(4, 72)];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7E7E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Hair Health Progress', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          SizedBox(
            height: 280,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 4,
                minY: 40,
                maxY: 100,
                lineTouchData: const LineTouchData(enabled: true),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: 10,
                  getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFEDEDED), strokeWidth: 1),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: const Border(
                    left: BorderSide(color: Color(0xFFD9D9D9)),
                    bottom: BorderSide(color: Color(0xFFD9D9D9)),
                    right: BorderSide.none,
                    top: BorderSide.none,
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
                      getTitlesWidget: (value, _) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6A6A6A)),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 28,
                      getTitlesWidget: (value, _) {
                        final i = value.toInt();
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
                    color: Colors.black,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                        radius: 3.6,
                        color: Colors.black,
                        strokeWidth: 1.2,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(show: true, color: const Color(0x14000000)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text('Hair Strength Over Time', style: TextStyle(fontSize: 12, color: Color(0xFF626262))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final displayName = (_patientName != null && _patientName!.isNotEmpty) ? _patientName! : (auth.userName ?? 'User');
    final photoUrl = (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) ? _profileImageUrl : auth.userPhotoUrl;
    final photoBytes = _profileImageBytes ?? auth.userPhotoBytes;
    final path = GoRouterState.of(context).matchedLocation;

    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 900;

    final content = Container(
      color: const Color(0xFFF5F5F5),
      child: Column(
        children: [
          _topBar(showMenu: !desktop, name: displayName, photoUrl: photoUrl, photoBytes: photoBytes, auth: auth),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(desktop ? 24 : 16, 20, desktop ? 24 : 16, 26),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1220),
                  child: Column(
                    children: [
                      _metricSection(desktop),
                      const SizedBox(height: 16),
                      if (desktop)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _reminderCard()),
                            const SizedBox(width: 14),
                            Expanded(child: _routineCard()),
                          ],
                        )
                      else ...[
                        _reminderCard(),
                        const SizedBox(height: 14),
                        _routineCard(),
                      ],
                      const SizedBox(height: 16),
                      _chartCard(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (!desktop) {
      return Scaffold(
        drawer: _sidebar(path, true),
        body: content,
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _sidebar(path, false),
          Expanded(child: content),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'Today';
    final str = date.toString();
    if (str.length >= 10) return str.substring(0, 10);
    return str;
  }
}

class _MetricData {
  const _MetricData(this.label, this.value);
  final String label;
  final int value;
}

class _MetricCircle extends StatelessWidget {
  const _MetricCircle(this.data);
  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7E7E7)),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 94,
            height: 94,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: data.value / 100,
                  strokeWidth: 9,
                  backgroundColor: const Color(0xFFE6E6E6),
                  valueColor: const AlwaysStoppedAnimation(Colors.black),
                ),
                Text('${data.value}%', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            data.label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem {
  const _SidebarItem(this.label, this.icon, this.route);
  final String label;
  final IconData icon;
  final String route;
}
import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/app_colors.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const double _sidebarWidth = 264;

  Map<String, dynamic>? _latestAnalysis;
  Map<String, dynamic>? _nextAppointment;
  String? _profileImageUrl;
  Uint8List? _profileImageBytes;
  String? _patientName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_latestAnalysis == null && _nextAppointment == null) _listenToData();
  }

  void _listenToData() {
    final userId = context.read<AuthProvider>().userId;
    if (FirebaseService.isInitialized) {
      final current = FirebaseService.currentUser;
      final authPhoto = current?.photoURL;
      final authName = current?.displayName;
      if (mounted) {
        setState(() {
          if (authPhoto != null && authPhoto.isNotEmpty) _profileImageUrl = authPhoto;
          if (authName != null && authName.trim().isNotEmpty) _patientName = authName.trim();
        });
      }
    }
    if (userId == null || !FirebaseService.isInitialized) return;

    FirebaseService.getPatientDetails(userId).then((snap) {
      if (!mounted || snap == null) return;
      final data = snap.data();
      final url = data?['profileImageUrl']?.toString();
      final b64 = data?['profileImageBase64']?.toString();
      final patientName = data?['name']?.toString();
      setState(() {
        if (url != null && url.isNotEmpty) _profileImageUrl = url;
        if (b64 != null && b64.isNotEmpty) {
          try {
            _profileImageBytes = base64Decode(b64);
          } catch (_) {}
        }
        if (patientName != null && patientName.trim().isNotEmpty) _patientName = patientName.trim();
      });
    });

    FirebaseService.getScalpAnalyses(userId).listen((snap) {
      if (!mounted || snap.docs.isEmpty) return;
      final rows = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList()
        ..sort((a, b) => (b['createdAt'] ?? '').toString().compareTo((a['createdAt'] ?? '').toString()));
      if (rows.isNotEmpty) setState(() => _latestAnalysis = rows.first);
    });

    FirebaseService.getAppointments(userId).listen((snap) {
      if (!mounted || snap.docs.isEmpty) return;
      for (final doc in snap.docs) {
        final d = doc.data();
        if (d['status'] == 'confirmed') {
          setState(() => _nextAppointment = {'id': doc.id, ...d});
          break;
        }
      }
    });
  }

  Future<void> _onProfileAction(String value, AuthProvider auth) async {
    if (value == 'settings') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings will be available soon.')),
      );
      return;
    }
    if (value == 'logout') {
      await auth.signOut();
      if (!mounted) return;
      context.go('/role');
    }
  }

  Widget _buildSidebar({
    required String currentPath,
    required bool collapsedMode,
  }) {
    bool selected(String path) => currentPath == path || (path != '/dashboard' && currentPath.startsWith(path));
    final items = <_NavItem>[
      _NavItem(label: 'Dashboard', icon: Icons.dashboard_outlined, route: '/dashboard'),
      _NavItem(label: 'My Scans', icon: Icons.document_scanner_outlined, route: '/scalp-analyzer'),
      _NavItem(label: 'Consultations', icon: Icons.people_outline, route: '/doctors'),
      _NavItem(label: 'Profile', icon: Icons.person_outline, route: '/patient-details'),
      _NavItem(label: 'Settings', icon: Icons.settings_outlined, route: ''),
    ];

    final content = Container(
      color: const Color(0xFFF7F7F7),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEFEFEF),
                      shape: BoxShape.circle,
                    ),
                    child: const Image(image: AssetImage('assets/logo.png')),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Safe Hair',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE3E3E3)),
            const SizedBox(height: 10),
            ...items.map((item) {
              final isSelected = item.route.isNotEmpty && selected(item.route);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Material(
                  color: isSelected ? const Color(0xFFEAEAEA) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (item.label == 'Settings') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Settings will be available soon.')),
                        );
                      } else if (item.route.isNotEmpty) {
                        context.go(item.route);
                      }
                      if (collapsedMode) Navigator.of(context).pop();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Row(
                        children: [
                          Icon(item.icon, color: Colors.black87, size: 22),
                          const SizedBox(width: 12),
                          Text(
                            item.label,
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );

    if (collapsedMode) return Drawer(width: _sidebarWidth, child: content);
    return SizedBox(width: _sidebarWidth, child: content);
  }

  Widget _buildTopBar({
    required bool showMenu,
    required String displayName,
    required String? photoUrl,
    required Uint8List? photoBytes,
    required AuthProvider auth,
  }) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8E8E8))),
      ),
      child: Row(
        children: [
          if (showMenu)
            Builder(
              builder: (ctx) => IconButton(
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                icon: const Icon(Icons.menu_rounded, color: Colors.black),
              ),
            ),
          Text(
            'Dashboard',
            style: TextStyle(
              fontSize: showMenu ? 24 : 26,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: 'Profile actions',
            onSelected: (value) => _onProfileAction(value, auth),
            itemBuilder: (_) => const [
              PopupMenuItem<String>(value: 'settings', child: Text('Settings')),
              PopupMenuItem<String>(value: 'logout', child: Text('Logout')),
            ],
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.black,
              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                  ? NetworkImage(photoUrl)
                  : (photoBytes != null ? MemoryImage(photoBytes) : null),
              child: ((photoUrl == null || photoUrl.isEmpty) && photoBytes == null)
                  ? Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  List<_MetricData> _metricData() {
    final m = _latestAnalysis;
    int read(dynamic value, int fallback) {
      if (value is num) return value.toInt().clamp(0, 100);
      if (value is String) return (int.tryParse(value) ?? fallback).clamp(0, 100);
      return fallback;
    }

    return [
      _MetricData('Hair Strength', read(m?['hairStrength'] ?? m?['hair_strength'], 72)),
      _MetricData('Scalp Health', read(m?['scalpHealth'] ?? m?['scalp_health'], 60)),
      _MetricData('Hair Damage Level', read(m?['hairDamageLevel'] ?? m?['hair_damage_level'], 45)),
      _MetricData('Hair Fall Risk', read(m?['hairFallRisk'] ?? m?['hair_fall_risk'], 80)),
    ];
  }

  Widget _buildMetricsSection(bool compactMode) {
    final metrics = _metricData();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEAEAEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your hair health',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.black),
          ),
          const SizedBox(height: 4),
          Text(
            'Last scan: ${_latestAnalysis == null ? 'Today' : _formatDate(_latestAnalysis!['createdAt'])}',
            style: const TextStyle(fontSize: 14, color: Color(0xFF5F5F5F)),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (_, constraints) {
              final desktopLike = !compactMode && constraints.maxWidth > 860;
              if (desktopLike) {
                return Row(
                  children: metrics
                      .map(
                        (m) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: _MetricCircle(data: m),
                          ),
                        ),
                      )
                      .toList(),
                );
              }
              return Wrap(
                spacing: 14,
                runSpacing: 16,
                children: metrics
                    .map(
                      (m) => SizedBox(
                        width: constraints.maxWidth < 520 ? constraints.maxWidth : (constraints.maxWidth - 14) / 2,
                        child: _MetricCircle(data: m),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReminderCard() {
    final dateText = _nextAppointment != null ? '${_nextAppointment!['date']} ${_nextAppointment!['timeSlot'] ?? ''}'.trim() : 'Today 10 AM';
    final bodyText = _nextAppointment != null
        ? 'Consultation with ${_nextAppointment!['doctorName'] ?? 'doctor'}'
        : 'Apply Hair Organic Oil';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Reminder', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.black)),
          const SizedBox(height: 10),
          Text(dateText, style: const TextStyle(fontSize: 16, color: Colors.black)),
          const SizedBox(height: 4),
          Text(bodyText, style: const TextStyle(fontSize: 14, color: Color(0xFF5A5A5A))),
        ],
      ),
    );
  }

  Widget _buildRoutineCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E1E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('AI Daily Routine', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.black)),
          const SizedBox(height: 10),
          const Text(
            'AI will analyze your hair and make an auto daily routine',
            style: TextStyle(fontSize: 14, color: Color(0xFF4A4A4A), height: 1.35),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Routine generator will be available soon.')),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            ),
            child: const Text('Generate Routine'),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard() {
    const weeks = ['Week 1', 'Week 2', 'Week 3', 'Week 4', 'Week 5'];
    const spots = <FlSpot>[
      FlSpot(0, 50),
      FlSpot(1, 60),
      FlSpot(2, 70),
      FlSpot(3, 80),
      FlSpot(4, 72),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hair Health Progress',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.black),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 280,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 4,
                minY: 40,
                maxY: 100,
                lineTouchData: const LineTouchData(enabled: true),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: 10,
                  getDrawingHorizontalLine: (value) => const FlLine(
                    color: Color(0xFFECECEC),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: const Border(
                    left: BorderSide(color: Color(0xFFD7D7D7)),
                    bottom: BorderSide(color: Color(0xFFD7D7D7)),
                    right: BorderSide.none,
                    top: BorderSide.none,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: 10,
                      getTitlesWidget: (value, _) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6B6B6B)),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 28,
                      getTitlesWidget: (value, _) {
                        final i = value.toInt();
                        if (i < 0 || i >= weeks.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            weeks[i],
                            style: const TextStyle(fontSize: 11, color: Color(0xFF6B6B6B)),
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
                    color: Colors.black,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                        radius: 3.8,
                        color: Colors.black,
                        strokeWidth: 1.4,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0x14000000),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Hair Strength Over Time',
            style: TextStyle(fontSize: 12, color: Color(0xFF636363)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final displayName = (_patientName != null && _patientName!.isNotEmpty) ? _patientName! : (auth.userName ?? 'User');
    final effectivePhotoUrl = (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) ? _profileImageUrl : auth.userPhotoUrl;
    final effectivePhotoBytes = _profileImageBytes ?? auth.userPhotoBytes;
    final path = GoRouterState.of(context).matchedLocation;

    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 900;

    final mainBody = Container(
      color: const Color(0xFFF5F5F5),
      child: Column(
        children: [
          _buildTopBar(
            showMenu: !desktop,
            displayName: displayName,
            photoUrl: effectivePhotoUrl,
            photoBytes: effectivePhotoBytes,
            auth: auth,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(desktop ? 26 : 16, 20, desktop ? 26 : 16, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1220),
                  child: Column(
                    children: [
                      _buildMetricsSection(!desktop),
                      const SizedBox(height: 16),
                      if (desktop)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildReminderCard()),
                            const SizedBox(width: 14),
                            Expanded(child: _buildRoutineCard()),
                          ],
                        )
                      else ...[
                        _buildReminderCard(),
                        const SizedBox(height: 14),
                        _buildRoutineCard(),
                      ],
                      const SizedBox(height: 16),
                      _buildChartCard(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (!desktop) {
      return Scaffold(
        drawer: _buildSidebar(currentPath: path, collapsedMode: true),
        body: mainBody,
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(currentPath: path, collapsedMode: false),
          Expanded(child: mainBody),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'Today';
    final str = date.toString();
    if (str.length >= 10) return str.substring(0, 10);
    return str;
  }
}

class _MetricData {
  const _MetricData(this.label, this.value);
  final String label;
  final int value;
}

class _MetricCircle extends StatelessWidget {
  const _MetricCircle({required this.data});
  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7E7E7)),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: data.value / 100,
                  strokeWidth: 10,
                  backgroundColor: const Color(0xFFE6E6E6),
                  valueColor: const AlwaysStoppedAnimation(Colors.black),
                ),
                Text(
                  '${data.value}%',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.black),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            data.label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final String route;
}
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/app_colors.dart';
import '../core/responsive.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/firebase_service.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/theme_toggle_control.dart';

/// Desktop web shell aligned with clinic dashboard (light grey canvas + sidebar).
class _PatientWebTheme {
  static const Color purple = Color(0xFF7B61FF);
  static const Color bg = Color(0xFFF5F6FA);
  static const Color sidebarBg = Color(0xFFFAFBFC);
  static const Color border = Color(0xFFE8EAED);
}

class _PatientNeoTheme {
  static const Color bg = Color(0xFFF4F7FB);
  static const Color panel = Color(0xFFFFFFFF);
  static const Color panelSoft = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFD9E4F2);
  static const Color text = Color(0xFF1A2A3A);
  static const Color muted = Color(0xFF6F7B8C);
  static const Color accent = Color(0xFF1F5AA8);
  static const Color darkBg = Color(0xFF0B1118);
  static const Color darkPanel = Color(0xFF121A24);
  static const Color darkPanelSoft = Color(0xFF162130);
  static const Color darkBorder = Color(0xFF263549);
  static const Color darkText = Color(0xFFEAF1FB);
  static const Color darkMuted = Color(0xFF98A8BD);
  static const Color darkAccent = Color(0xFF57A8FF);
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _latestAnalysis;
  Map<String, dynamic>? _nextAppointment;
  String? _profileImageUrl;
  Uint8List? _profileImageBytes;
  String? _patientName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_latestAnalysis == null && _nextAppointment == null) _listenToData();
  }

  void _listenToData() {
    final userId = context.read<AuthProvider>().userId;
    if (FirebaseService.isInitialized) {
      final current = FirebaseService.currentUser;
      final authPhoto = current?.photoURL;
      final authName = current?.displayName;
      if (mounted) {
        setState(() {
          if (authPhoto != null && authPhoto.isNotEmpty) _profileImageUrl = authPhoto;
          if (authName != null && authName.trim().isNotEmpty) _patientName = authName.trim();
        });
      }
    }
    if (userId == null || !FirebaseService.isInitialized) return;

    FirebaseService.getPatientDetails(userId).then((snap) {
      if (!mounted || snap == null) return;
      final data = snap.data();
      final url = data?['profileImageUrl']?.toString();
      final b64 = data?['profileImageBase64']?.toString();
      final patientName = data?['name']?.toString();
      setState(() {
        if (url != null && url.isNotEmpty) _profileImageUrl = url;
        if (b64 != null && b64.isNotEmpty) {
          try {
            _profileImageBytes = base64Decode(b64);
          } catch (_) {}
        }
        if (patientName != null && patientName.trim().isNotEmpty) _patientName = patientName.trim();
      });
    });

    FirebaseService.getScalpAnalyses(userId).listen((snap) {
      if (!mounted || snap.docs.isEmpty) return;
      final rows = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList()
        ..sort((a, b) => (b['createdAt'] ?? '').toString().compareTo((a['createdAt'] ?? '').toString()));
      if (rows.isNotEmpty) {
        setState(() => _latestAnalysis = rows.first);
      }
    });

    FirebaseService.getAppointments(userId).listen((snap) {
      if (mounted && snap.docs.isNotEmpty) {
        for (final doc in snap.docs) {
          final d = doc.data();
          if (d['status'] == 'confirmed') {
            setState(() => _nextAppointment = {'id': doc.id, ...d});
            break;
          }
        }
      }
    });
  }

  bool _usePatientWebLayout(BuildContext context) =>
      kIsWeb && MediaQuery.sizeOf(context).width >= 1000;

  String _currentRoutePath(BuildContext context) =>
      GoRouterState.of(context).matchedLocation;

  void _patientWebGo(BuildContext context, String path, {required bool hasAnalysis, bool needsAnalysis = false}) {
    if (needsAnalysis && !hasAnalysis) {
      _showOrderSnack('Complete AI Scalp Analysis first');
      return;
    }
    context.go(path);
  }

  Widget _buildPatientWebSidebar(BuildContext context, String name, bool hasAnalysis) {
    final loc = _currentRoutePath(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool sel(String path) => loc == path || (path != '/dashboard' && loc.startsWith(path));

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF12151C) : _PatientWebTheme.sidebarBg,
        border: Border(right: BorderSide(color: isDark ? const Color(0xFF2C3648) : _PatientWebTheme.border)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _PatientWebTheme.purple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.spa_outlined, color: _PatientWebTheme.purple, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Safe Hair',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                        Text(
                          'Patient',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : AppColors.textGrey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _PatientSideNavTile(
              icon: Icons.dashboard_outlined,
              label: 'Overview',
              selected: sel('/dashboard'),
              onTap: () => context.go('/dashboard'),
            ),
            _PatientSideNavTile(
              icon: Icons.document_scanner_outlined,
              label: 'AI Scalp Analysis',
              selected: sel('/scalp-analyzer'),
              onTap: () => context.go('/scalp-analyzer'),
            ),
            _PatientSideNavTile(
              icon: Icons.lightbulb_outline,
              label: 'Recommendations',
              selected: sel('/recommendations'),
              onTap: () => _patientWebGo(context, '/recommendations', hasAnalysis: hasAnalysis, needsAnalysis: true),
            ),
            _PatientSideNavTile(
              icon: Icons.medical_services_outlined,
              label: 'Book consultation',
              selected: sel('/doctors'),
              onTap: () => context.push('/doctors'),
            ),
            _PatientSideNavTile(
              icon: Icons.menu_book_outlined,
              label: 'Guidelines',
              selected: sel('/guidelines'),
              onTap: () => context.go('/guidelines'),
            ),
            _PatientSideNavTile(
              icon: Icons.description_outlined,
              label: 'My reports',
              selected: sel('/reports'),
              onTap: () => _patientWebGo(context, '/reports', hasAnalysis: hasAnalysis, needsAnalysis: true),
            ),
            const Spacer(),
            Divider(height: 1, color: isDark ? const Color(0xFF2C3648) : _PatientWebTheme.border),
            ListTile(
              leading: Icon(Icons.logout, color: isDark ? Colors.white54 : AppColors.textGrey, size: 22),
              title: Text(
                'Log out',
                style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : AppColors.textGrey),
              ),
              onTap: () async {
                await context.read<AuthProvider>().signOut();
                if (context.mounted) context.go('/role');
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : AppColors.textGrey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientWebTopBar(BuildContext context, AuthProvider auth, String name, String? effectivePhotoUrl, Uint8List? effectivePhotoBytes) {
    context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onBar = isDark ? Colors.white : AppColors.textDark;
    final onBarMuted = isDark ? Colors.white70 : AppColors.textGrey;
    return Material(
      color: isDark ? const Color(0xFF171B24) : Colors.white,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF2A3140) : _PatientWebTheme.border)),
        ),
        child: Row(
          children: [
            Text(
              'Overview',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: onBar),
            ),
            const Spacer(),
            Text(
              'Welcome back',
              style: TextStyle(fontSize: 13, color: onBarMuted),
            ),
            const SizedBox(width: 12),
            const ThemeToggleControl(),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Reports & activity',
              onPressed: () => context.push('/reports'),
              icon: Badge(
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 18),
                ),
              ),
            ),
            PopupMenuButton<String>(
              offset: const Offset(0, 40),
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.darkButton,
                  backgroundImage: (effectivePhotoUrl != null && effectivePhotoUrl.isNotEmpty)
                      ? NetworkImage(effectivePhotoUrl)
                      : (effectivePhotoBytes != null ? MemoryImage(effectivePhotoBytes) : null),
                  child: ((effectivePhotoUrl == null || effectivePhotoUrl.isEmpty) && effectivePhotoBytes == null)
                      ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: AppColors.white, fontSize: 16))
                      : null,
                ),
              ),
              onSelected: (value) async {
                if (value == 'logout') {
                  await auth.signOut();
                  if (context.mounted) context.go('/role');
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(value: 'logout', child: Text('Log out')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardBody({
    required BuildContext context,
    required AuthProvider auth,
    required String name,
    required String? effectivePhotoUrl,
    required Uint8List? effectivePhotoBytes,
    required bool isWide,
    required bool showMobileHeader,
    required bool showBottomNav,
    EdgeInsetsGeometry? padding,
  }) {
    context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairStrength = (_latestAnalysis?['hairStrength'] ?? _latestAnalysis?['hair_strength']) as num?;
    final scalpHealth = (_latestAnalysis?['scalpHealth'] ?? _latestAnalysis?['scalp_health']) as num?;
    final hairDensity = (_latestAnalysis?['hairDensity'] ?? _latestAnalysis?['hair_density']) as num?;
    final moisture = (_latestAnalysis?['moistureLevel'] ?? _latestAnalysis?['moisture_level']) as num?;
    final hasAnalysis = _latestAnalysis != null;
    final overallScore = (((hairStrength ?? 0) + (scalpHealth ?? 0) + (hairDensity ?? 0) + (moisture ?? 0)) / 4).round();

    final p = padding ?? const EdgeInsets.all(0);
    return Padding(
      padding: p,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showMobileHeader) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.darkButton,
                      backgroundImage: (effectivePhotoUrl != null && effectivePhotoUrl.isNotEmpty)
                          ? NetworkImage(effectivePhotoUrl)
                          : (effectivePhotoBytes != null ? MemoryImage(effectivePhotoBytes) : null),
                      child: ((effectivePhotoUrl == null || effectivePhotoUrl.isEmpty) && effectivePhotoBytes == null)
                          ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: AppColors.white, fontSize: 24))
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Good Morning!', style: TextStyle(fontSize: 14, color: _PatientNeoTheme.muted)),
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _PatientNeoTheme.text,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    const ThemeToggleControl(),
                    IconButton(
                      onPressed: () => context.push('/reports'),
                      icon: Badge(
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: const Icon(Icons.notifications, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: isDark ? Colors.white70 : AppColors.textDark),
                      onSelected: (value) async {
                        if (value == 'logout') {
                          await auth.signOut();
                          if (context.mounted) {
                            context.go('/role');
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem<String>(
                          value: 'logout',
                          child: Text('Log out'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? _PatientNeoTheme.darkPanel : _PatientNeoTheme.panel,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.05),
                  blurRadius: isDark ? 18 : 12,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: isDark ? _PatientNeoTheme.darkBorder : _PatientNeoTheme.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 20, color: isDark ? _PatientNeoTheme.darkAccent : _PatientNeoTheme.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Your Hair Health: Progress Since Last Scan',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? _PatientNeoTheme.darkText : _PatientNeoTheme.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _latestAnalysis != null ? 'Last Scan: ${_formatDate(_latestAnalysis!['createdAt'])}' : 'Last Scan: Complete analysis to see',
                  style: TextStyle(fontSize: 14, color: isDark ? _PatientNeoTheme.darkMuted : _PatientNeoTheme.muted),
                ),
                if (!hasAnalysis) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/scalp-analyzer'),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Start AI analysis to fill this card'),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _MetricCard(
                            title: 'Hair Strength',
                            value: hairStrength?.toInt(),
                            color: const Color(0xFF74D5C5),
                            width: isWide ? 190 : null,
                            isDark: isDark,
                          ),
                          _MetricCard(
                            title: 'Scalp Health',
                            value: scalpHealth?.toInt(),
                            color: const Color(0xFFE389E9),
                            width: isWide ? 190 : null,
                            isDark: isDark,
                          ),
                          _MetricCard(
                            title: 'Hair Density',
                            value: hairDensity?.toInt(),
                            color: const Color(0xFFE5E973),
                            width: isWide ? 190 : null,
                            isDark: isDark,
                          ),
                          _MetricCard(
                            title: 'Moisture',
                            value: moisture?.toInt(),
                            color: const Color(0xFF78A7D9),
                            width: isWide ? 190 : null,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                    if (isWide) ...[
                      const SizedBox(width: 14),
                      _OverallScoreCard(score: overallScore),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildReminderAndTip()),
                const SizedBox(width: 14),
                Expanded(child: _buildQuickActions(hasAnalysis, isDark)),
              ],
            )
          else ...[
            _buildReminderAndTip(),
            const SizedBox(height: 24),
            _buildQuickActions(hasAnalysis, isDark),
          ],
          if (showBottomNav) ...[
            const SizedBox(height: 24),
            const AppBottomNavBar(currentIndex: 0),
          ] else
            const SizedBox(height: 32),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = (_patientName != null && _patientName!.isNotEmpty) ? _patientName! : (auth.userName ?? 'User');
    final effectivePhotoUrl = (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) ? _profileImageUrl : auth.userPhotoUrl;
    final effectivePhotoBytes = _profileImageBytes ?? auth.userPhotoBytes;

    final hasAnalysis = _latestAnalysis != null;

    final useWebShell = _usePatientWebLayout(context);
    final padding = Responsive.horizontalPadding(context);
    final maxW = Responsive.maxContentWidth(context);
    final isWide = MediaQuery.sizeOf(context).width >= Responsive.tabletBreakpoint || useWebShell;

    if (useWebShell) {
      return Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? _PatientNeoTheme.darkBg
            : _PatientWebTheme.bg,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 248, child: _buildPatientWebSidebar(context, name, hasAnalysis)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPatientWebTopBar(context, auth, name, effectivePhotoUrl, effectivePhotoBytes),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1080),
                          child: _buildDashboardBody(
                            context: context,
                            auth: auth,
                            name: name,
                            effectivePhotoUrl: effectivePhotoUrl,
                            effectivePhotoBytes: effectivePhotoBytes,
                            isWide: true,
                            showMobileHeader: false,
                            showBottomNav: false,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? _PatientNeoTheme.darkBg
          : AppColors.primaryGreen,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW ?? double.infinity),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: _buildDashboardBody(
                context: context,
                auth: auth,
                name: name,
                effectivePhotoUrl: effectivePhotoUrl,
                effectivePhotoBytes: effectivePhotoBytes,
                isWide: isWide,
                showMobileHeader: true,
                showBottomNav: true,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'Today';
    final str = date.toString();
    if (str.length >= 10) return str.substring(0, 10);
    return str;
  }

  void _showOrderSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _buildReminderAndTip() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _PatientNeoTheme.darkPanelSoft : _PatientNeoTheme.panelSoft;
    final titleC = isDark ? _PatientNeoTheme.darkText : _PatientNeoTheme.text;
    final bodyC = isDark ? _PatientNeoTheme.darkMuted : _PatientNeoTheme.muted;
    return Column(
      children: [
        GestureDetector(
          onTap: () => context.push('/appointment'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? _PatientNeoTheme.darkBorder : _PatientNeoTheme.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.06),
                  blurRadius: isDark ? 16 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const Icon(Icons.notifications, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reminder',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: titleC),
                      ),
                      Text(
                        _nextAppointment != null ? '${_nextAppointment!['date']} at ${_nextAppointment!['timeSlot']}' : 'No upcoming appointment',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: bodyC),
                      ),
                      if (_nextAppointment != null)
                        Text(
                          'With ${_nextAppointment!['doctorName']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: bodyC),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => context.push('/appointment'),
                    icon: Icon(Icons.add_circle, color: isDark ? _PatientNeoTheme.darkAccent : _PatientNeoTheme.accent, size: 32),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () => context.push('/guidelines'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A2432) : const Color(0xFFF7FAFD),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? _PatientNeoTheme.darkBorder : _PatientNeoTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Spend 3 to 5 minutes every night massaging your scalp with your fingertips',
                    style: TextStyle(fontSize: 14, color: isDark ? _PatientNeoTheme.darkText : _PatientNeoTheme.text),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFFFF6F70) : const Color(0xFFFF5F61),
                    shape: BoxShape.circle,
                    boxShadow: isDark
                        ? [
                            BoxShadow(
                              color: const Color(0xFFFF6F70).withValues(alpha: 0.28),
                              blurRadius: 14,
                            ),
                          ]
                        : null,
                  ),
                  child: const Icon(Icons.auto_awesome, color: AppColors.white, size: 24),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(bool hasAnalysis, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 12) / 2;
        final cardHeight = cardWidth < 180 ? 150.0 : 132.0;
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: cardWidth / cardHeight,
          children: [
            _QuickActionCard(
              icon: Icons.camera_alt,
              label: 'AI Scalp Analysis',
              isDark: isDark,
              onTap: () => context.go('/scalp-analyzer'),
            ),
            _QuickActionCard(
              icon: Icons.lightbulb,
              label: 'Recommendations',
              isDark: isDark,
              onTap: hasAnalysis ? () => context.go('/recommendations') : () => _showOrderSnack('Complete AI Scalp Analysis first'),
            ),
            _QuickActionCard(
              icon: Icons.medical_services,
              label: 'Book Consultation',
              isDark: isDark,
              onTap: () => context.push('/doctors'),
            ),
            _QuickActionCard(
              icon: Icons.description,
              label: 'My Reports',
              isDark: isDark,
              onTap: hasAnalysis ? () => context.push('/reports') : () => _showOrderSnack('Generate a report by completing analysis first'),
            ),
          ],
        );
      },
    );
  }
}

class _PatientSideNavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PatientSideNavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveIcon = isDark ? Colors.white54 : AppColors.textGrey;
    final inactiveText = isDark ? Colors.white70 : AppColors.textGrey;
    final selectedText = isDark ? Colors.white : AppColors.textDark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected ? _PatientWebTheme.purple.withValues(alpha: isDark ? 0.22 : 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 22, color: selected ? _PatientWebTheme.purple : inactiveIcon),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 14,
                      color: selected ? selectedText : inactiveText,
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

class _MetricCard extends StatelessWidget {
  final String title;
  final int? value;
  final Color color;
  final double? width;
  final bool isDark;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.color,
    this.width,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final v = value;
    final fg = isDark ? _PatientNeoTheme.darkText : _PatientNeoTheme.text;
    final sub = isDark ? _PatientNeoTheme.darkMuted : _PatientNeoTheme.muted;
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 128),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? _PatientNeoTheme.darkPanelSoft : _PatientNeoTheme.panelSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? _PatientNeoTheme.darkBorder : _PatientNeoTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.05),
            blurRadius: isDark ? 12 : 8,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: sub)),
          const SizedBox(height: 12),
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: (v ?? 0) / 100,
                  strokeWidth: 7,
                  backgroundColor: color.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
                Text(
                  v == null ? '--' : '$v%',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: fg),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverallScoreCard extends StatelessWidget {
  final int score;
  const _OverallScoreCard({required this.score});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final value = score.clamp(0, 100) / 100.0;
    return Container(
      width: 220,
      constraints: const BoxConstraints(minHeight: 280),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: isDark ? _PatientNeoTheme.darkPanelSoft : const Color(0xFFF7FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? _PatientNeoTheme.darkBorder : const Color(0xFFD9E4F2)),
      ),
      child: Column(
        children: [
          Text(
            'Overall Score',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? _PatientNeoTheme.darkText : const Color(0xFF1D3557),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 118,
            height: 118,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: value,
                  strokeWidth: 12,
                  backgroundColor: isDark ? const Color(0xFF2A3A4D) : const Color(0xFFE6EDF7),
                  valueColor: AlwaysStoppedAnimation(isDark ? _PatientNeoTheme.darkAccent : const Color(0xFF2DAAB0)),
                ),
                Text(
                  '$score/100',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isDark ? _PatientNeoTheme.darkText : const Color(0xFF1A2A3A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your Hair Score',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? _PatientNeoTheme.darkMuted : const Color(0xFF6F7B8C),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final iconC = isDark ? _PatientNeoTheme.darkAccent : _PatientNeoTheme.accent;
    final textC = isDark ? _PatientNeoTheme.darkText : _PatientNeoTheme.text;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? _PatientNeoTheme.darkPanelSoft : _PatientNeoTheme.panelSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? _PatientNeoTheme.darkBorder : _PatientNeoTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.05),
              blurRadius: isDark ? 14 : 10,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: iconC),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textC),
            ),
          ],
        ),
      ),
    );
  }
}
