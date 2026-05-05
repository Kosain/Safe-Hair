import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'scalp_report_detail_screen.dart';

class _PendingRequest {
  const _PendingRequest({
    required this.id,
    required this.patientName,
    required this.dateTimeLabel,
    required this.reason,
  });
  final String id;
  final String patientName;
  final String dateTimeLabel;
  final String reason;
}

class _ConfirmedAppointment {
  const _ConfirmedAppointment({
    required this.id,
    required this.patientName,
    required this.dateTimeLabel,
    required this.reason,
  });
  final String id;
  final String patientName;
  final String dateTimeLabel;
  final String reason;
}

class _DoctorPatientListItem {
  const _DoctorPatientListItem(this.name, this.phone, this.lastVisit, this.consultations);
  final String name;
  final String phone;
  final String lastVisit;
  final int consultations;
}

const _kPracticePatients = <_DoctorPatientListItem>[
  _DoctorPatientListItem('Sana Khan', '+92 300 1122334', 'Apr 28, 2026', 5),
  _DoctorPatientListItem('Fatima Noor', '+92 321 4455667', 'Apr 22, 2026', 3),
  _DoctorPatientListItem('Ahmed Raza', '+92 333 7788990', 'Apr 18, 2026', 2),
  _DoctorPatientListItem('Hina Ali', '+92 345 2233445', 'Apr 10, 2026', 7),
  _DoctorPatientListItem('John Doe', '+92 301 9988776', 'Mar 30, 2026', 1),
  _DoctorPatientListItem('Umer Tariq', '+92 302 5544332', 'Mar 15, 2026', 4),
  _DoctorPatientListItem('Ayesha Malik', '+92 304 6677889', 'Mar 02, 2026', 2),
  _DoctorPatientListItem('Bilal Hussain', '+92 315 1122009', 'Feb 19, 2026', 6),
  _DoctorPatientListItem('Zara Sheikh', '+92 318 4455123', 'Feb 05, 2026', 3),
  _DoctorPatientListItem('Omar Farooq', '+92 322 9988001', 'Jan 22, 2026', 8),
];

class _DoctorMockVitals {
  const _DoctorMockVitals({required this.age, required this.gender, required this.summary});
  final String age;
  final String gender;
  final String summary;

  static _DoctorMockVitals fromPatientName(String patientName) {
    final pos = patientName.hashCode.abs();
    final age = 28 + pos % 28;
    final gender = pos.isEven ? 'Female' : 'Male';
    final score = 55 + pos % 36;
    final strength = 60 + pos % 30;
    final scalp = 58 + pos % 25;
    final issues =
        pos.isEven ? 'mild thinning at vertex, seasonal dryness' : 'minor inflammation at hairline, product buildup';
    return _DoctorMockVitals(
      age: '$age',
      gender: gender,
      summary:
          'Overall score: $score/100\nHair strength: $strength • Scalp health: $scalp\nDetected issues: $issues',
    );
  }
}

class DoctorDashboardScreen extends StatefulWidget {
  const DoctorDashboardScreen({super.key, this.section = 'dashboard'});

  final String section;

  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends State<DoctorDashboardScreen> {
  static const _stats = <_DoctorStat>[
    _DoctorStat('Total Patients', '1450', '+0.39%', true),
    _DoctorStat('New Patients', '63', '+0.62%', true),
    _DoctorStat('Old Patients', '313', '-0.12%', false),
    _DoctorStat('Appointments', '1971', '-2%', false),
  ];

  /// Life-stage groups; colors unchanged (was Child/Adult/Teen/Older palette).
  static const _ageGroups = <_DoctorAge>[
    _DoctorAge('Young Adult (18–30)', 170, 36, Color(0xFFF89A4C)),
    _DoctorAge('Adult (31–50)', 298, 32, Color(0xFF5D5FEF)),
    _DoctorAge('Mature (51–65)', 457, 21, Color(0xFF4CAF50)),
    _DoctorAge('Senior (65+)', 525, 12, Color(0xFF90CAF9)),
  ];

  static const _trend = <(String, int)>[
    ('Mon', 22),
    ('Tue', 28),
    ('Wed', 24),
    ('Thu', 30),
    ('Fri', 26),
    ('Sat', 18),
    ('Sun', 20),
  ];

  /// Shared across doctor dashboard / appointments routes so accept/decline persists in-session.
  static final List<_PendingRequest> _pendingRequests = [
    const _PendingRequest(
      id: 'r1',
      patientName: 'John Doe',
      dateTimeLabel: 'May 5, 2026 at 10:00 AM',
      reason: 'Hair thinning check',
    ),
    const _PendingRequest(
      id: 'r2',
      patientName: 'Hina Ali',
      dateTimeLabel: 'May 6, 2026 at 2:30 PM',
      reason: 'Scalp inflammation review',
    ),
    const _PendingRequest(
      id: 'r3',
      patientName: 'Ahmed Raza',
      dateTimeLabel: 'May 8, 2026 at 9:00 AM',
      reason: 'Dandruff consultation',
    ),
  ];

  static final List<_ConfirmedAppointment> _confirmedAppointments = [
    const _ConfirmedAppointment(
      id: 'c1',
      patientName: 'Sana Khan',
      dateTimeLabel: 'May 10, 2026 at 11:00 AM',
      reason: 'Post treatment follow-up',
    ),
    const _ConfirmedAppointment(
      id: 'c2',
      patientName: 'Fatima Noor',
      dateTimeLabel: 'May 12, 2026 at 1:15 PM',
      reason: 'Hair loss progression',
    ),
    const _ConfirmedAppointment(
      id: 'c3',
      patientName: 'Umer Tariq',
      dateTimeLabel: 'May 14, 2026 at 10:45 AM',
      reason: 'Routine checkup',
    ),
  ];

  List<(String, String, String, String)> get _dashboardUpcomingRows =>
      _confirmedAppointments.map((e) => (e.patientName, e.dateTimeLabel, e.reason, 'Confirmed')).toList();

  void _acceptRequest(String id) {
    final idx = _pendingRequests.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    final r = _pendingRequests[idx];
    setState(() {
      _pendingRequests.removeAt(idx);
      _confirmedAppointments.add(
        _ConfirmedAppointment(
          id: 'c_${DateTime.now().millisecondsSinceEpoch}',
          patientName: r.patientName,
          dateTimeLabel: r.dateTimeLabel,
          reason: r.reason,
        ),
      );
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Appointment confirmed with ${r.patientName}')),
    );
  }

  void _declineRequest(String id) {
    final idx = _pendingRequests.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    setState(() {
      _pendingRequests.removeAt(idx);
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment declined')));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDesktop = MediaQuery.sizeOf(context).width >= 1000;
    final active =
        widget.section == 'appointments' || widget.section == 'patients' ? widget.section : 'dashboard';
    final routePath = GoRouterState.of(context).uri.path;

    final Widget bodyBelowTopBar;
    if (active == 'appointments') {
      bodyBelowTopBar = Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        child: _DoctorAppointmentsPage(
          pending: _pendingRequests,
          confirmed: _confirmedAppointments,
          onAccept: _acceptRequest,
          onDecline: _declineRequest,
        ),
      );
    } else if (active == 'patients') {
      bodyBelowTopBar = const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 96),
        child: _DoctorPatientsSearchBody(),
      );
    } else {
      bodyBelowTopBar = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
        child: _DoctorDashboardMain(
          stats: _stats,
          ageGroups: _ageGroups,
          upcoming: _dashboardUpcomingRows,
          trend: _trend,
        ),
      );
    }

    final scrollBody = Container(
      color: const Color(0xFFF4F6F8),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DoctorTopBar(
              userName: auth.userName ?? 'Doctor',
              showMenuButton: !isDesktop,
            ),
            Expanded(child: bodyBelowTopBar),
          ],
        ),
      ),
    );

    if (!isDesktop) {
      return Scaffold(
        drawer: _DoctorSidebar(current: active),
        body: Stack(
          children: [
            Positioned.fill(child: scrollBody),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _DoctorFloatingBottomNav(currentPath: routePath),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Row(
              children: [
                _DoctorSidebar(current: active),
                Expanded(child: scrollBody),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _DoctorFloatingBottomNav(currentPath: routePath),
          ),
        ],
      ),
    );
  }
}

class _DoctorTopBar extends StatelessWidget {
  const _DoctorTopBar({
    required this.userName,
    this.showMenuButton = false,
  });

  final String userName;
  final bool showMenuButton;

  static Widget _brandRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset('assets/logo.png', width: 28, height: 28, fit: BoxFit.cover),
        ),
        const SizedBox(width: 8),
        const Text(
          'Safe Hair',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kToolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8E8E8))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showMenuButton)
            IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded, color: Colors.black87),
            ),
          if (showMenuButton) const SizedBox(width: 2),
          Expanded(
            child: Center(child: _brandRow()),
          ),
          PopupMenuButton<String>(
            tooltip: 'Profile',
            color: Colors.grey.shade100,
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'settings',
                child: Text('Settings', style: TextStyle(color: Colors.black)),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                child: Text('Logout', style: TextStyle(color: Colors.black)),
              ),
            ],
            onSelected: (value) async {
              if (value == 'settings') {
                if (context.mounted) context.push('/settings');
                return;
              }
              if (value == 'logout') {
                await context.read<AuthProvider>().signOut();
                if (context.mounted) context.go('/role');
              }
            },
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.black,
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : 'D',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoctorFloatingBottomNav extends StatelessWidget {
  const _DoctorFloatingBottomNav({required this.currentPath});

  final String currentPath;

  bool _selected(String route) {
    if (route == '/doctor-profile') {
      return currentPath == '/doctor-profile' || currentPath.startsWith('/doctor-profile/');
    }
    if (route == '/doctor-dashboard') {
      return currentPath == '/doctor-dashboard';
    }
    return currentPath == route || currentPath.startsWith('$route/');
  }

  @override
  Widget build(BuildContext context) {
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
            _DoctorNavItem(
              icon: Icons.home_rounded,
              label: 'Home',
              selected: _selected('/doctor-dashboard'),
              onTap: () => context.go('/doctor-dashboard'),
            ),
            _DoctorNavItem(
              icon: Icons.calendar_month_outlined,
              label: 'Appointments',
              selected: _selected('/doctor-appointments'),
              onTap: () => context.go('/doctor-appointments'),
            ),
            _DoctorNavItem(
              icon: Icons.people_outline,
              label: 'Patients',
              selected: _selected('/doctor-patients'),
              onTap: () => context.go('/doctor-patients'),
            ),
            _DoctorNavItem(
              icon: Icons.person_outline,
              label: 'Profile',
              selected: _selected('/doctor-profile'),
              onTap: () => context.go('/doctor-profile'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoctorNavItem extends StatelessWidget {
  const _DoctorNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF151515) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 22,
                color: selected ? Colors.white : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.black : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoctorSidebar extends StatelessWidget {
  const _DoctorSidebar({required this.current});

  final String current;
  static const _width = 260.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      child: Container(
        color: Colors.white,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(0xFFEFEFEF),
                      child: Image(image: AssetImage('assets/logo.png')),
                    ),
                    SizedBox(width: 10),
                    Text('Safe Hair', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.black)),
                  ],
                ),
              ),
              _SidebarItem(
                icon: Icons.dashboard_outlined,
                label: 'Dashboard',
                selected: current == 'dashboard',
                onTap: () => context.go('/doctor-dashboard'),
              ),
              _SidebarItem(
                icon: Icons.calendar_month_outlined,
                label: 'Appointments',
                selected: current == 'appointments',
                onTap: () => context.go('/doctor-appointments'),
              ),
              _SidebarItem(
                icon: Icons.people_outline,
                label: 'Patients',
                selected: current == 'patients',
                onTap: () => context.go('/doctor-patients'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: selected ? const Color(0xFFF0F0F0) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: Colors.black87),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

class _DoctorDashboardMain extends StatelessWidget {
  const _DoctorDashboardMain({
    required this.stats,
    required this.ageGroups,
    required this.upcoming,
    required this.trend,
  });

  final List<_DoctorStat> stats;
  final List<_DoctorAge> ageGroups;
  final List<(String, String, String, String)> upcoming;
  final List<(String, int)> trend;

  @override
  Widget build(BuildContext context) {
    final statGrid = Column(
      children: [
        Row(
          children: [
            Expanded(child: _StatCard(stat: stats[0])),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(stat: stats[1])),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _StatCard(stat: stats[2])),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(stat: stats[3])),
          ],
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        statGrid,
        const SizedBox(height: 16),
        _AgePieCard(ageGroups: ageGroups),
        const SizedBox(height: 16),
        _UpcomingAppointmentsCard(items: upcoming),
        const SizedBox(height: 16),
        _AppointmentTrendCard(points: trend),
      ],
    );
  }
}

class _UpcomingAppointmentsCard extends StatelessWidget {
  const _UpcomingAppointmentsCard({required this.items});
  final List<(String, String, String, String)> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Upcoming Appointments', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 12),
          SizedBox(
            height: 102,
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'No confirmed appointments',
                      style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
                    ),
                  )
                : ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                return Container(
                  width: 220,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 60,
                            height: 30,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(60, 30),
                                fixedSize: const Size(60, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                final mock = _DoctorMockVitals.fromPatientName(item.$1);
                                Navigator.of(context).push<void>(
                                  MaterialPageRoute<void>(
                                    builder: (ctx) => _DoctorPatientAppointmentDetailPage(
                                      patientName: item.$1,
                                      appointmentDateTime: item.$2,
                                      reason: item.$3,
                                      mockAge: mock.age,
                                      mockGender: mock.gender,
                                      mockAiSummary: mock.summary,
                                    ),
                                  ),
                                );
                              },
                              child: const Text('View', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 16, color: Color(0xFF6B7280)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(item.$2, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.medical_information_outlined, size: 16, color: Color(0xFF6B7280)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentTrendCard extends StatelessWidget {
  const _AppointmentTrendCard({required this.points});
  final List<(String, int)> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final spots = [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].$2.toDouble())];
    var minY = points.map((e) => e.$2).reduce(math.min).toDouble();
    var maxY = points.map((e) => e.$2).reduce(math.max).toDouble();
    if (maxY == minY) {
      minY -= 2;
      maxY += 2;
    }
    minY = math.max(0, minY - 4);
    maxY += 6;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Appointment Trends', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (points.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 5),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.round();
                        if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(points[idx].$1, style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563))),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    color: const Color(0xFF5D5FEF),
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    spots: spots,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});
  final _DoctorStat stat;

  @override
  Widget build(BuildContext context) {
    final trendColor = stat.positive ? const Color(0xFF2EAE56) : const Color(0xFFE05A63);
    IconData iconFor(String title) {
      if (title == 'Total Patients') return Icons.people_outline;
      if (title == 'New Patients') return Icons.person_add_alt_1_outlined;
      if (title == 'Old Patients') return Icons.person_outline;
      return Icons.calendar_today_outlined;
    }

    Color iconTint(String title) {
      if (title == 'Total Patients') return const Color(0xFF2563EB);
      if (title == 'New Patients') return const Color(0xFF7C3AED);
      if (title == 'Old Patients') return const Color(0xFF16A34A);
      return const Color(0xFFEA580C);
    }

    Color iconBg(String title) {
      if (title == 'Total Patients') return const Color(0xFFE8F1FE);
      if (title == 'New Patients') return const Color(0xFFF3E8FF);
      if (title == 'Old Patients') return const Color(0xFFE8F8EE);
      return const Color(0xFFFFF3E8);
    }

    final c = iconTint(stat.title);
    final bg = iconBg(stat.title);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(iconFor(stat.title), color: c, size: 22),
              ),
              const Spacer(),
              Text(
                stat.value,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(stat.title, style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(stat.positive ? Icons.trending_up : Icons.trending_down, color: trendColor, size: 18),
              const SizedBox(width: 2),
              Text(stat.change, style: TextStyle(color: trendColor, fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgePieCard extends StatefulWidget {
  const _AgePieCard({required this.ageGroups});
  final List<_DoctorAge> ageGroups;

  @override
  State<_AgePieCard> createState() => _AgePieCardState();
}

class _AgePieCardState extends State<_AgePieCard> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final ageGroups = widget.ageGroups;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Patient Age Groups', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SizedBox(
            height: 260,
            child: PieChart(
              PieChartData(
                centerSpaceRadius: 52,
                sectionsSpace: 2,
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                    if (!event.isInterestedForInteractions) {
                      setState(() => _touchedIndex = null);
                      return;
                    }
                    final touched = pieTouchResponse?.touchedSection;
                    if (touched == null) {
                      setState(() => _touchedIndex = null);
                      return;
                    }
                    setState(() => _touchedIndex = touched.touchedSectionIndex);
                  },
                ),
                sections: List.generate(
                  ageGroups.length,
                  (i) {
                    final g = ageGroups[i];
                    final touched = _touchedIndex == i;
                    return PieChartSectionData(
                      value: g.percent.toDouble(),
                      color: g.color,
                      radius: 62,
                      title: touched ? '${g.title}\n${g.count} (${g.percent}%)' : '${g.percent}%',
                      titleStyle: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: touched ? 10 : 12,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...ageGroups.map(
            (g) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: g.color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${g.title}: ${g.count} (${g.percent}%)',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoctorAppointmentsPage extends StatelessWidget {
  const _DoctorAppointmentsPage({
    required this.pending,
    required this.confirmed,
    required this.onAccept,
    required this.onDecline,
  });

  final List<_PendingRequest> pending;
  final List<_ConfirmedAppointment> confirmed;
  final void Function(String id) onAccept;
  final void Function(String id) onDecline;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            child: TabBar(
              indicator: const BoxDecoration(),
              labelColor: Colors.black,
              unselectedLabelColor: const Color(0xFF6B7280),
              dividerColor: Colors.transparent,
              dividerHeight: 0,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              tabs: const [
                Tab(text: 'Requests'),
                Tab(text: 'Upcoming'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              children: [
                _AppointmentRequestsList(pending: pending, onAccept: onAccept, onDecline: onDecline),
                _AppointmentUpcomingList(confirmed: confirmed),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentRequestsList extends StatelessWidget {
  const _AppointmentRequestsList({
    required this.pending,
    required this.onAccept,
    required this.onDecline,
  });

  final List<_PendingRequest> pending;
  final void Function(String id) onAccept;
  final void Function(String id) onDecline;

  @override
  Widget build(BuildContext context) {
    if (pending.isEmpty) {
      return const Center(
        child: Text(
          'No pending requests',
          style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600, fontSize: 15),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: pending.length,
      itemBuilder: (context, index) {
        final r = pending[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.patientName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.black),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.access_time, size: 18, color: Color(0xFF6B7280)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              r.dateTimeLabel,
                              style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.3),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.medical_information_outlined, size: 18, color: Color(0xFF6B7280)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              r.reason,
                              style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => onAccept(r.id),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.green.shade300, width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.check, color: Colors.green.shade300, size: 22),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => onDecline(r.id),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.red.shade300, width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.close, color: Colors.red.shade300, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AppointmentUpcomingList extends StatelessWidget {
  const _AppointmentUpcomingList({required this.confirmed});

  final List<_ConfirmedAppointment> confirmed;

  @override
  Widget build(BuildContext context) {
    if (confirmed.isEmpty) {
      return const Center(
        child: Text(
          'No upcoming appointments',
          style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600, fontSize: 15),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: confirmed.length,
      itemBuilder: (context, index) {
        final a = confirmed[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        a.patientName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.black),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 60,
                      height: 30,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(60, 30),
                          fixedSize: const Size(60, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          final mock = _DoctorMockVitals.fromPatientName(a.patientName);
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (ctx) => _DoctorPatientAppointmentDetailPage(
                                patientName: a.patientName,
                                appointmentDateTime: a.dateTimeLabel,
                                reason: a.reason,
                                mockAge: mock.age,
                                mockGender: mock.gender,
                                mockAiSummary: mock.summary,
                              ),
                            ),
                          );
                        },
                        child: const Text('View', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.access_time, size: 18, color: Color(0xFF6B7280)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        a.dateTimeLabel,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.medical_information_outlined, size: 18, color: Color(0xFF6B7280)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        a.reason,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DoctorPatientsSearchBody extends StatefulWidget {
  const _DoctorPatientsSearchBody();

  @override
  State<_DoctorPatientsSearchBody> createState() => _DoctorPatientsSearchBodyState();
}

class _DoctorPatientsSearchBodyState extends State<_DoctorPatientsSearchBody> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_DoctorPatientListItem> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _kPracticePatients;
    return _kPracticePatients
        .where((p) => p.name.toLowerCase().contains(q) || p.phone.toLowerCase().replaceAll(' ', '').contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search by name or phone...',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            prefixIcon: const Icon(Icons.search, color: Color(0xFF6B7280)),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF111111)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.builder(
            itemCount: _filtered.length,
            itemBuilder: (context, index) {
              final p = _filtered[index];
              final mock = _DoctorMockVitals.fromPatientName(p.name);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black)),
                          const SizedBox(height: 4),
                          Text(p.phone, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                          const SizedBox(height: 2),
                          Text('Last visit: ${p.lastVisit} • ${p.consultations} consultation(s)',
                              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 88,
                      height: 30,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(88, 30),
                          fixedSize: const Size(88, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (ctx) => _DoctorPatientAppointmentDetailPage(
                                patientName: p.name,
                                appointmentDateTime: 'Last visit: ${p.lastVisit}',
                                reason: '${p.consultations} consultation(s) with your practice',
                                practicePhone: p.phone,
                                mockAge: mock.age,
                                mockGender: mock.gender,
                                mockAiSummary: mock.summary,
                              ),
                            ),
                          );
                        },
                        child: const Text('View Profile', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DoctorPatientAppointmentDetailPage extends StatelessWidget {
  const _DoctorPatientAppointmentDetailPage({
    required this.patientName,
    required this.appointmentDateTime,
    required this.reason,
    required this.mockAge,
    required this.mockGender,
    required this.mockAiSummary,
    this.practicePhone,
  });

  final String patientName;
  final String appointmentDateTime;
  final String reason;
  final String mockAge;
  final String mockGender;
  final String mockAiSummary;
  final String? practicePhone;

  @override
  Widget build(BuildContext context) {
    Widget sectionTitle(String t) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black)),
      );
    }

    Widget infoRow(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 15, color: Color(0xFF374151), height: 1.35),
            children: [
              TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: value),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient details'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF4F6F8),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          sectionTitle('Patient'),
          infoRow('Name', patientName),
          infoRow('Age', mockAge),
          infoRow('Gender', mockGender),
          if (practicePhone != null && practicePhone!.isNotEmpty) infoRow('Phone', practicePhone!),
          const SizedBox(height: 20),
          sectionTitle('AI scalp analysis (summary)'),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              mockAiSummary,
              style: const TextStyle(fontSize: 15, color: Color(0xFF374151), height: 1.4),
            ),
          ),
          const SizedBox(height: 20),
          sectionTitle('Appointment'),
          infoRow('Date & time', appointmentDateTime),
          infoRow('Reason', reason),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (ctx) => const ScalpReportDetailScreen(reportId: 'doctor-preview'),
                  ),
                );
              },
              child: const Text('View Full AI Report', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoctorStat {
  const _DoctorStat(this.title, this.value, this.change, this.positive);
  final String title;
  final String value;
  final String change;
  final bool positive;
}

class _DoctorAge {
  const _DoctorAge(this.title, this.count, this.percent, this.color);
  final String title;
  final int count;
  final int percent;
  final Color color;
}
