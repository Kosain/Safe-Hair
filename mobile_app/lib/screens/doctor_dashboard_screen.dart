import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../core/app_colors.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/firebase_service.dart';
import '../widgets/theme_toggle_control.dart';

/// Mediwave-inspired clinic dashboard: sidebar, overview KPIs, appointment grid.
class DoctorDashboardScreen extends StatefulWidget {
  const DoctorDashboardScreen({super.key});

  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _ClinicDashTheme {
  static const Color purple = Color(0xFF7B61FF);
  static const Color blue = Color(0xFF4A90E2);
  static const Color coral = Color(0xFFF45B4B);
  static const Color green = Color(0xFF27AE60);
  static const Color bg = Color(0xFFF5F6FA);
  static const Color sidebarBg = Color(0xFFFAFBFC);
  static const Color border = Color(0xFFE8EAED);
  static const Color darkCard = Color(0xFF1F2633);
  static const Color darkBorder = Color(0xFF2D3748);
}

String _normApptDate(Map<String, dynamic> m) {
  final d = m['date']?.toString() ?? '';
  return d.length >= 10 ? d.substring(0, 10) : d;
}

String _formatTrendPercent(int current, int previous) {
  if (previous == 0) return current == 0 ? '0%' : '+100%';
  final pct = ((current - previous) / previous * 100).round();
  return pct >= 0 ? '+$pct%' : '$pct%';
}

String _patientInitialsFrom(String? patientName, String fallbackId) {
  final n = patientName?.trim();
  if (n != null && n.isNotEmpty) {
    final p = n.split(RegExp(r'\s+'));
    if (p.length >= 2) return '${p[0][0]}${p[1][0]}'.toUpperCase();
    return (n.length >= 2 ? n.substring(0, 2) : n.substring(0, 1))
        .toUpperCase();
  }
  return fallbackId.length >= 2
      ? fallbackId.substring(0, 2).toUpperCase()
      : 'P';
}

String _patientDisplayName(Map<String, dynamic> data) {
  final n = data['patientName']?.toString();
  if (n != null && n.isNotEmpty) return n;
  final uid = data['userId']?.toString() ?? '';
  if (uid.length >= 6) return 'Patient ${uid.substring(0, 6)}…';
  return 'Patient';
}

Future<void> _doctorDashDeleteAppointment(
  BuildContext context,
  String docId,
) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Remove appointment?'),
      content: const Text(
        'This permanently deletes this booking from the schedule.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  final ok = await FirebaseService.deleteAppointment(docId);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        ok
            ? 'Appointment removed'
            : 'Could not delete. Check connection and rules.',
      ),
    ),
  );
}

Future<void> _doctorDashCompleteAppointment(
  BuildContext context,
  String docId,
  Map<String, dynamic> data,
) async {
  final st = (data['status'] ?? '').toString().toLowerCase();
  if (st == 'completed') {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Already marked completed')));
    return;
  }
  if (st == 'declined' || st == 'cancelled') {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cannot complete a cancelled booking')),
    );
    return;
  }
  final ok = await FirebaseService.updateAppointment(docId, {
    'status': 'completed',
    'completedAt': DateTime.now().toIso8601String(),
  });
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        ok ? 'Marked as completed' : 'Could not update. Try again.',
      ),
    ),
  );
}

Future<void> _doctorDashDeclineAppointment(
  BuildContext context,
  String docId,
  Map<String, dynamic> data,
) async {
  final st = (data['status'] ?? '').toString().toLowerCase();
  if (st == 'declined') {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Already declined')));
    return;
  }
  if (st == 'completed') {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Visit already completed')));
    return;
  }
  final ok = await FirebaseService.updateAppointment(docId, {
    'status': 'declined',
  });
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        ok ? 'Appointment declined' : 'Could not update. Try again.',
      ),
    ),
  );
}

class _ApptMetrics {
  final int appointmentsToday;
  final int appointmentsYesterday;
  final int completedToday;
  final int completedYesterday;
  final int cancelledToday;
  final int cancelledYesterday;
  final int urgentToday;
  final int urgentYesterday;
  final int dailyCapacity;

  const _ApptMetrics({
    required this.appointmentsToday,
    required this.appointmentsYesterday,
    required this.completedToday,
    required this.completedYesterday,
    required this.cancelledToday,
    required this.cancelledYesterday,
    required this.urgentToday,
    required this.urgentYesterday,
    required this.dailyCapacity,
  });

  static _ApptMetrics compute(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required String today,
    required String yesterday,
    int dailyCapacity = 30,
  }) {
    bool isCancelledLike(String? s) {
      final x = (s ?? '').toLowerCase();
      return x == 'cancelled' || x == 'declined';
    }

    bool isCompleted(String? s) => (s ?? '').toLowerCase() == 'completed';

    /// Upcoming / active bookings (not yet completed or rejected).
    bool isScheduledActive(String? s) {
      final x = (s ?? 'confirmed').toLowerCase();
      if (isCancelledLike(s) || isCompleted(s)) return false;
      return x == 'confirmed' || x == 'pending' || x.isEmpty;
    }

    bool isUrgent(Map<String, dynamic> m) {
      if ((m['priority'] ?? '').toString().toLowerCase() == 'urgent') {
        return true;
      }
      return (m['consultationNotes'] ?? '').toString().toLowerCase().contains(
        'urgent',
      );
    }

    int apT = 0, apY = 0, cT = 0, cY = 0, xT = 0, xY = 0, uT = 0, uY = 0;
    for (final d in docs) {
      final m = d.data();
      final date = _normApptDate(m);
      final st = m['status']?.toString();
      if (date == today) {
        if (isScheduledActive(st)) apT++;
        if (isCompleted(st)) cT++;
        if (isCancelledLike(st)) xT++;
        if (isUrgent(m) && isScheduledActive(st)) uT++;
      }
      if (date == yesterday) {
        if (isScheduledActive(st)) apY++;
        if (isCompleted(st)) cY++;
        if (isCancelledLike(st)) xY++;
        if (isUrgent(m) && isScheduledActive(st)) uY++;
      }
    }
    return _ApptMetrics(
      appointmentsToday: apT,
      appointmentsYesterday: apY,
      completedToday: cT,
      completedYesterday: cY,
      cancelledToday: xT,
      cancelledYesterday: xY,
      urgentToday: uT,
      urgentYesterday: uY,
      dailyCapacity: dailyCapacity,
    );
  }
}

class _DoctorDashboardScreenState extends State<DoctorDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _navIndex = 0;
  bool _gridView = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Uint8List? _tryDecodeB64(dynamic s) {
    if (s == null) return null;
    final str = s.toString();
    if (str.isEmpty) return null;
    try {
      return base64Decode(str);
    } catch (_) {
      return null;
    }
  }

  String _todayStr() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<void> _openClinicSettings(String userId) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.event_note_outlined),
              title: const Text('Check appointments'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _navIndex = 1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Change password'),
              subtitle: const Text('Send password reset email'),
              onTap: () async {
                Navigator.pop(ctx);
                final email = context.read<AuthProvider>().userEmail;
                if (email == null || email.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No email found for this account.'),
                    ),
                  );
                  return;
                }
                try {
                  await FirebaseService.auth.sendPasswordResetEmail(
                    email: email,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Password reset email sent to $email'),
                    ),
                  );
                } catch (_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Could not send reset email. Please try again.',
                      ),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: const Text('Add doctor'),
              onTap: () async {
                Navigator.pop(ctx);
                final profile = await FirebaseService.getDoctorProfile(userId);
                if (!mounted) return;
                await _showAddDoctorDialog(
                  userId,
                  profile ?? const <String, dynamic>{},
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDoctorDialog(
    String userId,
    Map<String, dynamic> profile,
  ) async {
    final nameCtrl = TextEditingController();
    final domainCtrl = TextEditingController();
    final qualCtrl = TextEditingController();
    final feeCtrl = TextEditingController();
    final expCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add doctor'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Doctor name'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                TextFormField(
                  controller: domainCtrl,
                  decoration: const InputDecoration(labelText: 'Speciality'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                TextFormField(
                  controller: qualCtrl,
                  decoration: const InputDecoration(labelText: 'Qualification'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                TextFormField(
                  controller: feeCtrl,
                  decoration: const InputDecoration(labelText: 'Fee'),
                  keyboardType: TextInputType.number,
                ),
                TextFormField(
                  controller: expCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Experience (years)',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final current = (profile['activeDoctorsData'] is List)
        ? List<Map<String, dynamic>>.from(
            (profile['activeDoctorsData'] as List).map(
              (e) => Map<String, dynamic>.from(e as Map),
            ),
          )
        : <Map<String, dynamic>>[];
    current.add({
      'name': nameCtrl.text.trim(),
      'domain': domainCtrl.text.trim(),
      'speciality': domainCtrl.text.trim(),
      'qualification': qualCtrl.text.trim(),
      'fee': int.tryParse(feeCtrl.text.trim()) ?? 0,
      'experienceYears': int.tryParse(expCtrl.text.trim()) ?? 0,
    });
    await FirebaseService.saveDoctorProfile({
      'userId': userId,
      'activeDoctorsData': current,
      'activeDoctorsCount': current.length,
      'profileCompleted': true,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Doctor added successfully.')));
  }

  Widget _docPreview({required String title, String? url, Uint8List? b64}) {
    Widget content;
    if (url != null && url.isNotEmpty) {
      content = Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 100,
      );
    } else if (b64 != null) {
      content = Image.memory(
        b64,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 100,
      );
    } else {
      content = Container(
        height: 100,
        color: AppColors.cardBackground,
        child: const Center(
          child: Icon(Icons.description_outlined, color: AppColors.textGrey),
        ),
      );
    }
    return Container(
      width: 160,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _ClinicDashTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: Container(
                    color: Colors.black,
                    padding: const EdgeInsets.all(8),
                    child: InteractiveViewer(child: content),
                  ),
                ),
              );
            },
            child: content,
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              title,
              style: const TextStyle(fontSize: 11, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = auth.userName ?? 'Clinic';
    final userId = auth.userId;
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1000;

    if (userId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!FirebaseService.isInitialized) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF10131A) : _ClinicDashTheme.bg,
        appBar: AppBar(
          title: const Text('Clinic Dashboard'),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: ThemeToggleControl(),
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: _ClinicDashTheme.purple.withValues(
                    alpha: 0.2,
                  ),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'C',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: _ClinicDashTheme.purple,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Welcome, $name',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Clinic account is active. Connect Firebase to enable appointments and analytics widgets.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () async {
                    await context.read<AuthProvider>().signOut();
                    if (context.mounted) context.go('/role');
                  },
                  child: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isDark ? const Color(0xFF10131A) : _ClinicDashTheme.bg,
      drawer: isDesktop ? null : _buildDrawer(context, userId, name),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isDesktop)
            SizedBox(width: 248, child: _buildSidebar(context, userId, name)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopBar(context, auth, isDesktop: isDesktop),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseService.getAppointmentsForDoctor(userId),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? [];
                      return StreamBuilder<
                        DocumentSnapshot<Map<String, dynamic>>
                      >(
                        stream: FirebaseService.firestore
                            .collection('doctors')
                            .doc(userId)
                            .snapshots(),
                        builder: (context, profSnap) {
                          final p =
                              profSnap.data?.data() ??
                              const <String, dynamic>{};
                          return _buildMainContent(
                            context,
                            userId: userId,
                            name: name,
                            profile: p,
                            docs: docs,
                            loading:
                                snap.connectionState == ConnectionState.waiting,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, String userId, String name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      backgroundColor: isDark
          ? const Color(0xFF171B24)
          : _ClinicDashTheme.sidebarBg,
      child: SafeArea(child: _sidebarColumn(context, userId, name)),
    );
  }

  Widget _buildSidebar(BuildContext context, String userId, String name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF171B24) : _ClinicDashTheme.sidebarBg,
      child: SafeArea(child: _sidebarColumn(context, userId, name)),
    );
  }

  Widget _sidebarColumn(BuildContext context, String userId, String name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseService.getAppointmentsForDoctor(userId),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final apptBadge = docs.length.clamp(0, 999);
        final patientIds = docs
            .map((d) => d.data()['userId']?.toString())
            .whereType<String>()
            .toSet();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _ClinicDashTheme.purple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.favorite,
                      color: _ClinicDashTheme.purple,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Safe Hair',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
            _SideNavTile(
              icon: Icons.dashboard_outlined,
              label: 'Dashboard',
              selected: _navIndex == 0,
              onTap: () => setState(() => _navIndex = 0),
            ),
            _SideNavTile(
              icon: Icons.event_note_outlined,
              label: 'Appointments',
              badge: apptBadge > 0 ? '$apptBadge' : null,
              selected: _navIndex == 1,
              onTap: () => setState(() => _navIndex = 1),
            ),
            _SideNavTile(
              icon: Icons.calendar_today_outlined,
              label: 'Calendar',
              selected: _navIndex == 2,
              onTap: () => setState(() => _navIndex = 2),
            ),
            _SideNavTile(
              icon: Icons.people_outline,
              label: 'Patients',
              badge: patientIds.isNotEmpty
                  ? '${patientIds.length.clamp(0, 99)}'
                  : null,
              selected: _navIndex == 3,
              onTap: () => setState(() => _navIndex = 3),
            ),
            _SideNavTile(
              icon: Icons.medical_services_outlined,
              label: 'Team',
              selected: _navIndex == 4,
              onTap: () => setState(() => _navIndex = 4),
            ),
            _SideNavTile(
              icon: Icons.storefront_outlined,
              label: 'Clinic',
              selected: _navIndex == 5,
              onTap: () => setState(() => _navIndex = 5),
            ),
            const Spacer(),
            const Divider(height: 1),
            _SideNavTile(
              icon: Icons.settings_outlined,
              label: 'Settings',
              selected: false,
              onTap: () => _openClinicSettings(userId),
            ),
            _SideNavTile(
              icon: Icons.help_outline,
              label: 'Help',
              selected: false,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Contact support from your clinic admin.'),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.logout,
                color: isDark ? Colors.white54 : AppColors.textGrey,
                size: 22,
              ),
              title: Text(
                'Log out',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : AppColors.textGrey,
                ),
              ),
              onTap: () async {
                await context.read<AuthProvider>().signOut();
                if (context.mounted) context.go('/role');
              },
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    AuthProvider auth, {
    required bool isDesktop,
  }) {
    context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onBar = isDark ? Colors.white : AppColors.textDark;
    final onBarMuted = isDark ? Colors.white70 : Colors.grey.shade600;
    String title;
    switch (_navIndex) {
      case 1:
        title = 'Appointments';
        break;
      case 2:
        title = 'Calendar';
        break;
      case 3:
        title = 'Patients';
        break;
      case 4:
        title = 'Team';
        break;
      case 5:
        title = 'Clinic';
        break;
      default:
        title = 'Dashboard';
    }

    final searchBg = isDark ? const Color(0xFF1B2230) : _ClinicDashTheme.bg;
    final searchHint = isDark ? Colors.white38 : Colors.grey.shade500;
    final canShowWideSearch = MediaQuery.sizeOf(context).width >= 980;
    return Container(
      padding: EdgeInsets.fromLTRB(isDesktop ? 28 : 12, 12, 20, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171B24) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF2A3140) : _ClinicDashTheme.border,
          ),
        ),
      ),
      child: Row(
        children: [
          if (!isDesktop)
            IconButton(
              icon: Icon(Icons.menu, color: onBar),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: onBar,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '›',
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.grey.shade400,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _navIndex == 0 ? 'Overview' : title,
            style: TextStyle(fontSize: 14, color: onBarMuted),
          ),
          const Spacer(),
          const ThemeToggleControl(),
          if (isDesktop && canShowWideSearch) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 220,
              height: 40,
              child: TextField(
                controller: _searchController,
                onChanged: (v) =>
                    setState(() => _searchQuery = v.trim().toLowerCase()),
                style: TextStyle(color: onBar),
                decoration: InputDecoration(
                  hintText: 'Search…',
                  hintStyle: TextStyle(fontSize: 13, color: searchHint),
                  prefixIcon: Icon(Icons.search, size: 20, color: searchHint),
                  filled: true,
                  fillColor: searchBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: Icon(Icons.apps, color: onBarMuted),
              onPressed: () {},
            ),
            IconButton(
              icon: Icon(Icons.notifications_none, color: onBarMuted),
              onPressed: () {},
            ),
          ],
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              if (context.mounted) context.go('/role');
            },
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.white : AppColors.textDark,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Logout'),
          ),
          const SizedBox(width: 4),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: auth.userId == null
                ? null
                : FirebaseService.firestore
                      .collection('doctors')
                      .doc(auth.userId)
                      .snapshots(),
            builder: (context, snap) {
              final p = snap.data?.data() ?? const <String, dynamic>{};
              final b64 = _tryDecodeB64(p['ownerProfileImageBase64']);
              final url = p['ownerProfileImageUrl']?.toString();
              if (url != null && url.isNotEmpty) {
                return CircleAvatar(
                  radius: 18,
                  backgroundImage: NetworkImage(url),
                );
              }
              if (b64 != null) {
                return CircleAvatar(
                  radius: 18,
                  backgroundImage: MemoryImage(b64),
                );
              }
              return CircleAvatar(
                radius: 18,
                backgroundColor: _ClinicDashTheme.purple.withValues(alpha: 0.2),
                child: Text(
                  (auth.userName ?? 'C').isNotEmpty
                      ? (auth.userName ?? 'C')[0].toUpperCase()
                      : 'C',
                  style: const TextStyle(
                    color: _ClinicDashTheme.purple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(
    BuildContext context, {
    required String userId,
    required String name,
    required Map<String, dynamic> profile,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required bool loading,
  }) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (_navIndex) {
      case 2:
        return _calendarView(docs);
      case 3:
        return _patientsView(docs);
      case 4:
        return _teamView(userId, profile);
      case 5:
        return _clinicProfileView(userId, name, profile);
      case 1:
        return _appointmentsOnlyView(docs);
      default:
        return _dashboardView(context, profile, docs);
    }
  }

  Widget _calendarView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _ClinicDashTheme.darkCard : Colors.white;
    final borderColor = isDark
        ? _ClinicDashTheme.darkBorder
        : _ClinicDashTheme.border;
    final textPrimary = isDark ? Colors.white : AppColors.textDark;
    final textMuted = isDark ? Colors.white70 : Colors.grey.shade600;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TableCalendar<DateTime>(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2035, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
              onDaySelected: (selected, focused) {
                setState(() {
                  _selectedDay = selected;
                  _focusedDay = focused;
                });
              },
              onPageChanged: (focused) => setState(() => _focusedDay = focused),
              eventLoader: (day) {
                final key = DateFormat('yyyy-MM-dd').format(day);
                final n = docs
                    .where((e) => _normApptDate(e.data()) == key)
                    .length;
                return n > 0 ? List<DateTime>.generate(n, (_) => day) : [];
              },
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: _ClinicDashTheme.purple.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: const BoxDecoration(
                  color: _ClinicDashTheme.purple,
                  shape: BoxShape.circle,
                ),
                markerDecoration: const BoxDecoration(
                  color: _ClinicDashTheme.blue,
                  shape: BoxShape.circle,
                ),
                defaultTextStyle: TextStyle(color: textPrimary),
                weekendTextStyle: TextStyle(color: textPrimary),
                outsideTextStyle: TextStyle(
                  color: textMuted.withValues(alpha: 0.55),
                ),
              ),
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
                leftChevronIcon: Icon(Icons.chevron_left, color: textMuted),
                rightChevronIcon: Icon(Icons.chevron_right, color: textMuted),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Appointments on ${DateFormat.yMMMd().format(_selectedDay)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Builder(
              builder: (context) {
                final key = DateFormat('yyyy-MM-dd').format(_selectedDay);
                final dayDocs =
                    docs.where((e) => _normApptDate(e.data()) == key).toList()
                      ..sort(
                        (a, b) => (a.data()['timeSlot'] ?? '')
                            .toString()
                            .compareTo((b.data()['timeSlot'] ?? '').toString()),
                      );
                if (dayDocs.isEmpty) {
                  return Center(
                    child: Text(
                      'No appointments on this day',
                      style: TextStyle(color: textMuted),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: dayDocs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _AppointmentListTile(
                    data: dayDocs[i].data(),
                    id: dayDocs[i].id,
                    dense: false,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _patientsView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : AppColors.textDark;
    final textMuted = isDark ? Colors.white70 : Colors.grey.shade600;
    final cardBg = isDark ? _ClinicDashTheme.darkCard : Colors.white;
    final cardBorder = isDark
        ? _ClinicDashTheme.darkBorder
        : _ClinicDashTheme.border;
    final idToName = <String, String>{};
    for (final d in docs) {
      final m = d.data();
      final uid = m['userId']?.toString();
      if (uid == null || uid.isEmpty) continue;
      final pn = m['patientName']?.toString().trim();
      if (pn != null && pn.isNotEmpty) idToName[uid] = pn;
    }
    final ids = docs
        .map((d) => d.data()['userId']?.toString())
        .whereType<String>()
        .toSet();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '${ids.length} unique patients (from bookings)',
          style: TextStyle(color: textMuted),
        ),
        const SizedBox(height: 16),
        ...ids.map(
          (id) => Card(
            color: cardBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: cardBorder),
            ),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _ClinicDashTheme.blue.withValues(alpha: 0.15),
                child: Text(
                  _patientInitialsFrom(idToName[id], id),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              title: Text(
                idToName[id] ??
                    'Patient ${id.length >= 8 ? id.substring(0, 8) : id}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              subtitle: Text('ID: $id', style: TextStyle(color: textMuted)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _teamView(String userId, Map<String, dynamic> p) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : AppColors.textDark;
    final textMuted = isDark ? Colors.white70 : Colors.grey.shade600;
    final cardBg = isDark ? _ClinicDashTheme.darkCard : Colors.white;
    final cardBorder = isDark
        ? _ClinicDashTheme.darkBorder
        : _ClinicDashTheme.border;
    final team = p['activeDoctorsData'];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text(
              'Clinic Doctors',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _showAddDoctorDialog(userId, p),
              icon: const Icon(Icons.add),
              label: const Text('Add doctor'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (team is! List || team.isEmpty)
          Text(
            'Add your team in Clinic registration.',
            style: TextStyle(color: textMuted),
          )
        else
          ...team.map<Widget>((e) {
            final m = e is Map ? e : const {};
            return Card(
              color: cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: cardBorder),
              ),
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const Icon(
                  Icons.person_outline,
                  color: _ClinicDashTheme.purple,
                ),
                title: Text(
                  '${m['name'] ?? ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                subtitle: Text(
                  '${m['domain'] ?? ''} · ${m['qualification'] ?? ''}',
                  style: TextStyle(color: textMuted),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _clinicProfileView(
    String userId,
    String name,
    Map<String, dynamic> p,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : AppColors.textDark;
    final textMuted = isDark ? Colors.white70 : Colors.grey.shade600;
    final clinicName = (p['clinicName'] ?? p['fullName'] ?? name).toString();
    final clinicLocation = (p['clinicLocation'] ?? p['address'] ?? 'Not set')
        .toString();
    final licenseB64 = _tryDecodeB64(p['licenseDocBase64']);
    final qualB64 = _tryDecodeB64(p['qualificationDocBase64']);
    final addB64 = _tryDecodeB64(p['additionalDocBase64']);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            clinicName,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(clinicLocation, style: TextStyle(color: textMuted)),
          const SizedBox(height: 24),
          Text(
            'Documents',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _docPreview(
                title: 'Medical License',
                url: p['licenseDocUrl']?.toString(),
                b64: licenseB64,
              ),
              _docPreview(
                title: 'Qualification',
                url: p['qualificationDocUrl']?.toString(),
                b64: qualB64,
              ),
              _docPreview(
                title: 'Additional',
                url: p['additionalDocUrl']?.toString(),
                b64: addB64,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _appointmentsOnlyView(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final filtered = _filterDocs(docs);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _appointmentToolbar(filtered.length),
          const SizedBox(height: 16),
          _appointmentBody(filtered),
        ],
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (_searchQuery.isEmpty) return docs;
    return docs.where((d) {
      final m = d.data();
      final blob =
          '${m['userId']} ${m['date']} ${m['timeSlot']} ${m['consultationNotes']} ${m['patientName']}'
              .toLowerCase();
      return blob.contains(_searchQuery);
    }).toList();
  }

  Widget _dashboardView(
    BuildContext context,
    Map<String, dynamic> profile,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : AppColors.textDark;
    final textMuted = isDark ? Colors.white70 : Colors.grey.shade600;
    final today = _todayStr();
    final yesterday = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime.now().subtract(const Duration(days: 1)));
    final capRaw = profile['dailyConsultationCapacity'];
    final dailyCap = (capRaw is num)
        ? capRaw.toInt()
        : int.tryParse('$capRaw') ?? 30;
    final metrics = _ApptMetrics.compute(
      docs,
      today: today,
      yesterday: yesterday,
      dailyCapacity: dailyCap,
    );

    final todayDocs = docs
        .where((d) => _normApptDate(d.data()) == today)
        .toList();
    final displayDocs = todayDocs.isNotEmpty ? todayDocs : docs;
    final filtered = _filterDocs(displayDocs);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Overview',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const Spacer(),
              _filterChip(
                'Clinic',
                (profile['clinicLocation'] ?? 'All locations').toString(),
              ),
              const SizedBox(width: 8),
              _filterChip('Date', "Today's"),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final cross = w > 1100 ? 4 : (w > 700 ? 2 : 1);
              return GridView.count(
                crossAxisCount: cross,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: cross == 1 ? 2.4 : 1.45,
                children: [
                  _KpiCard(
                    title: 'Appointments',
                    value: '${metrics.appointmentsToday}',
                    subtitle: "Today's",
                    color: _ClinicDashTheme.blue,
                    trend: _formatTrendPercent(
                      metrics.appointmentsToday,
                      metrics.appointmentsYesterday,
                    ),
                    trendUp:
                        metrics.appointmentsToday >=
                        metrics.appointmentsYesterday,
                    icon: Icons.bar_chart_rounded,
                  ),
                  _KpiCard(
                    title: 'Consultations',
                    value: '${metrics.completedToday}',
                    subtitle: "Today's",
                    color: _ClinicDashTheme.purple,
                    trend: _formatTrendPercent(
                      metrics.completedToday,
                      metrics.completedYesterday,
                    ),
                    trendUp:
                        metrics.completedToday >= metrics.completedYesterday,
                    icon: Icons.pie_chart_outline,
                    extra: '${metrics.completedToday}/${metrics.dailyCapacity}',
                  ),
                  _KpiCard(
                    title: 'Cancelled',
                    value: '${metrics.cancelledToday}',
                    subtitle: "Today's",
                    color: _ClinicDashTheme.coral,
                    trend: _formatTrendPercent(
                      metrics.cancelledToday,
                      metrics.cancelledYesterday,
                    ),
                    trendUp:
                        metrics.cancelledToday <= metrics.cancelledYesterday,
                    icon: Icons.bar_chart_rounded,
                  ),
                  _KpiCard(
                    title: 'Urgent',
                    value: '${metrics.urgentToday}',
                    subtitle: 'Resolve',
                    color: _ClinicDashTheme.green,
                    trend: _formatTrendPercent(
                      metrics.urgentToday,
                      metrics.urgentYesterday,
                    ),
                    trendUp: metrics.urgentToday <= metrics.urgentYesterday,
                    icon: Icons.emergency_outlined,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Today's",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  Text(
                    '${filtered.length} Appointments',
                    style: TextStyle(fontSize: 13, color: textMuted),
                  ),
                ],
              ),
              const Spacer(),
              _appointmentToolbar(filtered.length),
            ],
          ),
          const SizedBox(height: 16),
          _appointmentBody(filtered),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? _ClinicDashTheme.darkCard : Colors.white;
    final borderColor = isDark
        ? _ClinicDashTheme.darkBorder
        : _ClinicDashTheme.border;
    final textMuted = isDark ? Colors.white70 : Colors.grey.shade600;
    final textPrimary = isDark ? Colors.white : AppColors.textDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(fontSize: 12, color: textMuted)),
          Text(
            value.length > 24 ? '${value.substring(0, 24)}…' : value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
          Icon(Icons.arrow_drop_down, size: 18, color: textMuted),
        ],
      ),
    );
  }

  Widget _appointmentToolbar(int count) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white70 : Colors.grey.shade600;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$count shown', style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(width: 12),
        IconButton(
          icon: Icon(
            Icons.view_list,
            color: _gridView ? muted : _ClinicDashTheme.purple,
          ),
          onPressed: () => setState(() => _gridView = false),
        ),
        IconButton(
          icon: Icon(
            Icons.grid_view,
            color: _gridView ? _ClinicDashTheme.purple : muted,
          ),
          onPressed: () => setState(() => _gridView = true),
        ),
      ],
    );
  }

  Widget _appointmentBody(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (docs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: isDark ? _ClinicDashTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? _ClinicDashTheme.darkBorder
                : _ClinicDashTheme.border,
          ),
        ),
        child: Column(
          children: [
            Icon(Icons.event_available, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No appointments yet',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    if (!_gridView) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: docs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) =>
            _AppointmentListTile(data: docs[i].data(), id: docs[i].id),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cols = w > 1200 ? 4 : (w > 900 ? 3 : (w > 520 ? 2 : 1));
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.72,
          ),
          itemCount: docs.length,
          itemBuilder: (context, i) =>
              _AppointmentCard(data: docs[i].data(), id: docs[i].id),
        );
      },
    );
  }
}

class _SideNavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _SideNavTile({
    required this.icon,
    required this.label,
    this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveIcon = isDark ? Colors.white54 : AppColors.textGrey;
    final inactiveText = isDark ? Colors.white70 : AppColors.textDark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected
            ? _ClinicDashTheme.purple.withValues(alpha: isDark ? 0.2 : 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected ? _ClinicDashTheme.purple : inactiveIcon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 14,
                      color: selected ? _ClinicDashTheme.purple : inactiveText,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: label == 'Patients'
                          ? _ClinicDashTheme.blue.withValues(alpha: 0.15)
                          : _ClinicDashTheme.purple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: label == 'Patients'
                            ? _ClinicDashTheme.blue
                            : _ClinicDashTheme.purple,
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

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final String trend;
  final bool trendUp;
  final IconData icon;
  final String? extra;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.trend,
    required this.trendUp,
    required this.icon,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _ClinicDashTheme.darkCard : Colors.white;
    final borderColor = isDark
        ? _ClinicDashTheme.darkBorder
        : Colors.transparent;
    final titleColor = isDark ? Colors.white70 : Colors.grey.shade600;
    final valueColor = isDark ? Colors.white : AppColors.textDark;
    final subtitleColor = isDark ? Colors.white60 : Colors.grey.shade500;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (trendUp ? Colors.green : Colors.red).withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  trend,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: trendUp
                        ? Colors.green.shade700
                        : Colors.red.shade600,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(title, style: TextStyle(fontSize: 13, color: titleColor)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: subtitleColor),
                ),
              ),
            ],
          ),
          if (extra != null)
            Text(extra!, style: TextStyle(fontSize: 12, color: titleColor)),
        ],
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String id;

  const _AppointmentCard({required this.data, required this.id});

  void _showDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Appointment'),
        content: SingleChildScrollView(
          child: Text(
            'Name: ${_patientDisplayName(data)}\n'
            'User ID: ${data['userId'] ?? '—'}\n'
            'Date: ${data['date'] ?? '—'}\n'
            'Time: ${data['timeSlot'] ?? '—'}\n'
            'Status: ${data['status'] ?? '—'}\n'
            'Priority: ${data['priority'] ?? '—'}\n'
            'Notes: ${data['consultationNotes'] ?? '—'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _ClinicDashTheme.darkCard : Colors.white;
    final borderColor = isDark
        ? _ClinicDashTheme.darkBorder
        : Colors.transparent;
    final textPrimary = isDark ? Colors.white : AppColors.textDark;
    final textMuted = isDark ? Colors.white70 : Colors.grey.shade700;
    final date = data['date']?.toString() ?? '—';
    final time = data['timeSlot']?.toString() ?? '—';
    final dateShow = date.length >= 10 ? date.substring(0, 10) : date;
    final uid = data['userId']?.toString() ?? '';

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        onTap: () => _showDetails(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                    onPressed: () => _doctorDashDeleteAppointment(context, id),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                    onPressed: () =>
                        _doctorDashCompleteAppointment(context, id, data),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                    onPressed: () =>
                        _doctorDashDeclineAppointment(context, id, data),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: _ClinicDashTheme.blue.withValues(
                    alpha: 0.15,
                  ),
                  child: Text(
                    _patientInitialsFrom(data['patientName']?.toString(), uid),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _ClinicDashTheme.blue,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _patientDisplayName(data),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Consultation',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: textMuted),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.access_time, size: 14, color: textMuted),
                  const SizedBox(width: 4),
                  Text(time, style: TextStyle(fontSize: 12, color: textMuted)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 12,
                    color: textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    dateShow,
                    style: TextStyle(fontSize: 12, color: textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _showDetails(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? const Color(0xFF29364A)
                        : const Color(0xFF1E3A5F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('VIEW DETAILS'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppointmentListTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String id;
  final bool dense;

  const _AppointmentListTile({
    required this.data,
    required this.id,
    this.dense = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _ClinicDashTheme.darkCard : Colors.white;
    final borderColor = isDark
        ? _ClinicDashTheme.darkBorder
        : Colors.transparent;
    final textPrimary = isDark ? Colors.white : AppColors.textDark;
    final textMuted = isDark ? Colors.white70 : Colors.grey.shade700;
    final uid = data['userId']?.toString() ?? '';
    return Card(
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: ListTile(
        dense: dense,
        leading: CircleAvatar(
          backgroundColor: _ClinicDashTheme.purple.withValues(alpha: 0.15),
          child: Text(
            _patientInitialsFrom(data['patientName']?.toString(), uid),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _ClinicDashTheme.purple,
            ),
          ),
        ),
        title: Text(
          _patientDisplayName(data),
          style: TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
        ),
        subtitle: Text(
          '${data['timeSlot'] ?? '—'} · ${_normApptDate(data)} · ${data['status'] ?? 'confirmed'}',
          style: TextStyle(color: textMuted),
        ),
        isThreeLine: false,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: Colors.grey.shade500,
              ),
              onPressed: () => _doctorDashDeleteAppointment(context, id),
            ),
            IconButton(
              icon: Icon(
                Icons.check_circle_outline,
                size: 20,
                color: Colors.grey.shade500,
              ),
              onPressed: () =>
                  _doctorDashCompleteAppointment(context, id, data),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 20, color: Colors.grey.shade500),
              onPressed: () => _doctorDashDeclineAppointment(context, id, data),
            ),
          ],
        ),
      ),
    );
  }
}
