import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/safe_hair_colors.dart';
import '../l10n/tr.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
import 'doctor_review_dialog.dart';

class PatientWebScaffold extends StatefulWidget {
  const PatientWebScaffold({
    super.key,
    required this.currentRoute,
    required this.body,
    this.backgroundColor = const Color(0xFFF4FAF6),
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bodyScrollController,
    this.showScrollbar = false,
    this.extraScrollBottomPadding = 0,
  });

  final String currentRoute;
  final Widget body;
  final Color backgroundColor;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final ScrollController? bodyScrollController;
  final bool showScrollbar;
  /// Extra bottom inset so content clears the floating bottom nav when present.
  final double extraScrollBottomPadding;

  @override
  State<PatientWebScaffold> createState() => _PatientWebScaffoldState();
}

class _PatientWebScaffoldState extends State<PatientWebScaffold> {
  bool _reviewPromptChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptDoctorReview());
  }

  Future<void> _maybePromptDoctorReview() async {
    if (_reviewPromptChecked) return;
    _reviewPromptChecked = true;
    if (!mounted) return;
    if (!widget.currentRoute.startsWith('/my-appointments')) return;
    final auth = context.read<AuthProvider>();
    if (auth.role != 'patient') return;
    final uid = auth.userId;
    if (uid == null || uid.isEmpty || !FirebaseService.isInitialized) return;
    final pending = await FirebaseService.getNextPendingDoctorReview(uid);
    if (!mounted || pending == null) return;
    await FirebaseService.markReviewPromptShownForDoctor(
      patientUserId: uid,
      doctorId: pending.doctorId,
    );
    await FirebaseService.markReviewPromptShown(pending.appointmentId);
    if (!mounted) return;
    await showDoctorReviewDialog(context, pending: pending);
  }

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    final auth = context.watch<AuthProvider>();
    final name = auth.userName ?? 'User';
    final scaffoldBg = Theme.of(context).brightness == Brightness.dark ? sh.scaffold : widget.backgroundColor;
    final photoUrl = auth.userPhotoUrl;
    final photoBytes = auth.userPhotoBytes;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    final scrollPadding = EdgeInsets.fromLTRB(
      isDesktop ? 24 : 16,
      16,
      isDesktop ? 24 : 16,
      24 + widget.extraScrollBottomPadding,
    );

    Widget scrollChild = SingleChildScrollView(
      controller: widget.bodyScrollController,
      padding: scrollPadding,
      child: widget.body,
    );
    if (widget.showScrollbar && widget.bodyScrollController != null) {
      scrollChild = Scrollbar(
        controller: widget.bodyScrollController,
        thumbVisibility: true,
        child: scrollChild,
      );
    }

    final content = Container(
      color: scaffoldBg,
      child: Column(
        children: [
          _TopProfileBar(name: name, photoUrl: photoUrl, photoBytes: photoBytes),
          Expanded(child: scrollChild),
        ],
      ),
    );

    if (!isDesktop) {
      return Scaffold(
        drawer: _Sidebar(currentRoute: widget.currentRoute, inDrawer: true),
        body: Stack(
          children: [
            Positioned.fill(child: content),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _PatientFloatingBottomNav(currentRoute: widget.currentRoute),
            ),
          ],
        ),
        floatingActionButton: widget.floatingActionButton,
        floatingActionButtonLocation: widget.floatingActionButtonLocation,
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(currentRoute: widget.currentRoute, inDrawer: false),
          Expanded(child: content),
        ],
      ),
      floatingActionButton: widget.floatingActionButton,
      floatingActionButtonLocation: widget.floatingActionButtonLocation,
    );
  }
}

class _TopProfileBar extends StatefulWidget {
  const _TopProfileBar({
    required this.name,
    required this.photoUrl,
    required this.photoBytes,
  });

  final String name;
  final String? photoUrl;
  final Uint8List? photoBytes;

  @override
  State<_TopProfileBar> createState() => _TopProfileBarState();
}

class _TopProfileBarState extends State<_TopProfileBar> {
  String? _patientImageUrl;
  Uint8List? _patientImageBytes;
  String? _patientName;

  @override
  void initState() {
    super.initState();
    _loadPatientAvatar();
  }

  Future<void> _loadPatientAvatar() async {
    final uid = context.read<AuthProvider>().userId;
    if (uid == null || !FirebaseService.isInitialized) return;
    final snap = await FirebaseService.getPatientDetails(uid);
    if (!mounted || snap == null || !snap.exists) return;
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
      if (url != null && url.isNotEmpty) _patientImageUrl = url;
      if (decoded != null) _patientImageBytes = decoded;
      if (patientName != null && patientName.trim().isNotEmpty) _patientName = patientName.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final topInset = MediaQuery.paddingOf(context).top;
    final displayName =
        (_patientName != null && _patientName!.isNotEmpty) ? _patientName! : widget.name;
    final effectivePhotoUrl =
        (_patientImageUrl != null && _patientImageUrl!.isNotEmpty) ? _patientImageUrl : widget.photoUrl;
    final effectivePhotoBytes = _patientImageBytes ?? widget.photoBytes;
    final sh = context.sh;
    return Container(
      height: 64 + (isDesktop ? 0 : topInset),
      padding: EdgeInsets.fromLTRB(16, isDesktop ? 0 : topInset, 16, 0),
      decoration: BoxDecoration(
        color: sh.card,
        border: Border(bottom: BorderSide(color: sh.border)),
      ),
      child: Row(
        children: [
          if (!isDesktop)
            Builder(
              builder: (ctx) => IconButton(
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                icon: Icon(Icons.menu_rounded, color: context.sh.textPrimary),
              ),
            ),
          const Spacer(),
          if (auth.role == 'patient' && auth.userId != null && FirebaseService.isInitialized)
            _PatientAppointmentNotificationBell(userId: auth.userId!),
          if (auth.role == 'patient' && auth.userId != null && FirebaseService.isInitialized)
            const SizedBox(width: 4),
          PopupMenuButton<String>(
            color: context.sh.card,
            itemBuilder: (ctx) => [
              PopupMenuItem<String>(
                value: 'settings',
                child: Text(ctx.t('settings'), style: TextStyle(color: ctx.sh.textPrimary)),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                child: Text(ctx.t('logout'), style: TextStyle(color: ctx.sh.textPrimary)),
              ),
            ],
            onSelected: (value) async {
              if (value == 'settings') {
                context.push('/settings');
                return;
              }
              await auth.signOut();
              if (context.mounted) context.go('/role');
            },
            child: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF2B2B2B),
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
        ],
      ),
    );
  }
}

/// Bell + badge; opens a scrollable card anchored under the icon.
class _PatientAppointmentNotificationBell extends StatefulWidget {
  const _PatientAppointmentNotificationBell({required this.userId});

  final String userId;

  @override
  State<_PatientAppointmentNotificationBell> createState() => _PatientAppointmentNotificationBellState();
}

class _PatientAppointmentNotificationBellState extends State<_PatientAppointmentNotificationBell> {
  final GlobalKey _bellKey = GlobalKey();

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _unreadAppointmentDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((d) {
      final m = d.data();
      if (m['read'] == true) return false;
      return (m['type'] ?? 'appointment').toString() == 'appointment';
    }).toList();
  }

  void _showPanel(BuildContext context, List<QueryDocumentSnapshot<Map<String, dynamic>>> items) {
    final sh = context.sh;
    final box = _bellKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
    const cardWidth = 380.0;
    final screenW = overlay.size.width;
    var left = bottomRight.dx - cardWidth;
    if (left < 12) left = 12;
    if (left + cardWidth > screenW - 12) left = screenW - cardWidth - 12;

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close notifications',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, _, __) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: bottomRight.dy + 8,
              width: cardWidth,
              child: Material(
                elevation: 10,
                shadowColor: Colors.black45,
                color: sh.card,
                borderRadius: BorderRadius.circular(14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Appointment updates',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: sh.textPrimary,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.close, color: sh.textSecondary, size: 20),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: sh.border),
                        Flexible(
                          child: items.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                    'No new updates.',
                                    style: TextStyle(color: sh.textSecondary),
                                  ),
                                )
                              : Scrollbar(
                                  thumbVisibility: true,
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    itemCount: items.length,
                                    separatorBuilder: (_, __) => Divider(height: 1, color: sh.border),
                                    itemBuilder: (context, index) {
                                      final d = items[index];
                                      final m = d.data();
                                      final title = (m['title'] ?? 'Update').toString();
                                      final body = (m['body'] ?? '').toString();
                                      final event = (m['event'] ?? '').toString();
                                      final isConfirmed =
                                          event == 'confirmed' || title.toLowerCase().contains('confirmed');
                                      return ListTile(
                                        dense: true,
                                        leading: Icon(
                                          isConfirmed ? Icons.check_circle_outline : Icons.info_outline,
                                          color: isConfirmed ? const Color(0xFF2E7D32) : Colors.deepOrange.shade800,
                                        ),
                                        title: Text(
                                          title,
                                          style: TextStyle(fontWeight: FontWeight.w600, color: sh.textPrimary),
                                        ),
                                        subtitle: body.isNotEmpty
                                            ? Text(body, style: TextStyle(fontSize: 13, color: sh.textSecondary))
                                            : null,
                                        trailing: TextButton(
                                          onPressed: () => FirebaseService.markPatientNotificationRead(d.id),
                                          child: const Text('Dismiss'),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                        Divider(height: 1, color: sh.border),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            context.go('/my-appointments');
                          },
                          child: const Text('Open My Appointments'),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseService.patientNotificationsStream(widget.userId),
      builder: (context, snap) {
        final unread = _unreadAppointmentDocs(snap.data?.docs ?? const []);
        final hasConfirmed = unread.any((d) {
          final m = d.data();
          final event = (m['event'] ?? '').toString();
          final title = (m['title'] ?? '').toString().toLowerCase();
          return event == 'confirmed' || title.contains('confirmed');
        });
        return IconButton(
          key: _bellKey,
          tooltip: unread.isEmpty
              ? 'No appointment updates'
              : hasConfirmed
                  ? 'Doctor confirmed your appointment'
                  : 'Appointment update',
          onPressed: () => _showPanel(context, unread),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                unread.isEmpty ? Icons.notifications_none_outlined : Icons.notifications_active_outlined,
                color: sh.textPrimary,
              ),
              if (unread.isNotEmpty)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: hasConfirmed ? const Color(0xFF2E7D32) : Colors.deepOrange,
                      shape: BoxShape.circle,
                      border: Border.all(color: sh.card, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.currentRoute,
    required this.inDrawer,
  });

  static const _sidebarWidth = 264.0;

  final String currentRoute;
  final bool inDrawer;

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    final items = <(String, IconData, String)>[
      (context.t('nav_dashboard'), Icons.dashboard_outlined, '/dashboard'),
      (context.t('nav_my_scans'), Icons.document_scanner_outlined, '/my-scans'),
      (context.t('nav_my_appointments'), Icons.calendar_month_outlined, '/my-appointments'),
      (context.t('nav_my_reports'), Icons.description_outlined, '/my-report'),
      (context.t('nav_my_chats'), Icons.chat_bubble_outline, '/chat-list'),
    ];

    bool isSelected(String route) {
      if (route == '/chat-list') {
        return currentRoute == '/chat-list' || currentRoute.startsWith('/chat/');
      }
      return currentRoute == route || (route != '/dashboard' && currentRoute.startsWith(route));
    }

    final panel = Container(
      color: sh.card,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(0xFFEFEFEF),
                    child: Image(image: AssetImage('assets/logo.png')),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    context.t('app_name'),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: sh.textPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            ...items.map((item) {
              final selected = isSelected(item.$3);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                child: Material(
                  color: selected ? sh.sidebarSelectedBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      context.go(item.$3);
                      if (inDrawer) Navigator.of(context).pop();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Row(
                        children: [
                          Icon(item.$2, color: sh.icon),
                          const SizedBox(width: 12),
                          Text(
                            item.$1,
                            style: TextStyle(
                              color: sh.textPrimary,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

    if (inDrawer) return Drawer(width: _sidebarWidth, child: panel);
    return SizedBox(width: _sidebarWidth, child: panel);
  }
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

    final sh = context.sh;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        height: 74,
        decoration: BoxDecoration(
          color: sh.navBar,
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
              sh: sh,
            ),
            _BottomNavItem(
              icon: Icons.crop_free_rounded,
              selected: selected('/my-scans'),
              onTap: () => context.go('/my-scans'),
              sh: sh,
            ),
            _BottomNavItem(
              icon: Icons.calendar_month_outlined,
              selected: selected('/my-appointments'),
              onTap: () => context.go('/my-appointments'),
              sh: sh,
            ),
            _BottomNavItem(
              icon: Icons.description_outlined,
              selected: selected('/my-report'),
              onTap: () => context.go('/my-report'),
              sh: sh,
            ),
            if (!kIsWeb)
              _BottomNavItem(
                icon: Icons.chat_outlined,
                selected: selected('/chat-list'),
                onTap: () => context.go('/chat-list'),
                sh: sh,
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
    required this.sh,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final SafeHairColors sh;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 50,
        height: 48,
        decoration: BoxDecoration(
          color: selected ? sh.selectedNavBg : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 24,
          color: selected ? sh.selectedNavFg : sh.unselectedNavFg,
        ),
      ),
    );
  }
}
