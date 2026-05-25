import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/safe_hair_colors.dart';
import '../l10n/tr.dart';

/// Doctor shell for chat routes only (sidebar + optional mobile bottom nav).
class DoctorChatShell extends StatelessWidget {
  const DoctorChatShell({
    super.key,
    required this.child,
    this.currentPath = '/chat-list',
  });

  final Widget child;
  final String currentPath;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    if (!isDesktop) {
      return Scaffold(
        drawer: Drawer(
          width: _DoctorChatSidebarPanel.width,
          child: const _DoctorChatSidebarPanel(inDrawer: true),
        ),
        body: Stack(
          children: [
            Positioned.fill(child: child),
            if (!kIsWeb)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _DoctorChatBottomNav(currentPath: currentPath),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DoctorChatSidebarPanel(inDrawer: false),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _DoctorChatSidebarPanel extends StatelessWidget {
  const _DoctorChatSidebarPanel({required this.inDrawer});

  static const width = 260.0;

  final bool inDrawer;

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).matchedLocation;
    final onChat = path.startsWith('/chat');
    final sh = context.sh;

    Widget item({
      required IconData icon,
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Material(
          color: selected ? sh.sidebarSelectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, color: sh.icon),
                  const SizedBox(width: 12),
                  Text(
                    label,
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
    }

    void go(String route) {
      context.go(route);
      if (inDrawer) Navigator.of(context).pop();
    }

    return Container(
      width: width,
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
            item(
              icon: Icons.dashboard_outlined,
              label: context.t('nav_dashboard'),
              selected: path == '/doctor-dashboard',
              onTap: () => go('/doctor-dashboard'),
            ),
            item(
              icon: Icons.calendar_month_outlined,
              label: context.t('nav_appointments'),
              selected: path.startsWith('/doctor-appointments'),
              onTap: () => go('/doctor-appointments'),
            ),
            item(
              icon: Icons.people_outline,
              label: context.t('nav_patients'),
              selected: path.startsWith('/doctor-patients'),
              onTap: () => go('/doctor-patients'),
            ),
            item(
              icon: Icons.chat_bubble_outline,
              label: context.t('nav_my_chats'),
              selected: onChat,
              onTap: () => go('/chat-list'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoctorChatBottomNav extends StatelessWidget {
  const _DoctorChatBottomNav({required this.currentPath});

  final String currentPath;

  bool _selected(String route) {
    if (route == '/chat-list') {
      return currentPath.startsWith('/chat');
    }
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
            _NavItem(
              icon: Icons.home_rounded,
              label: context.t('nav_home'),
              selected: _selected('/doctor-dashboard'),
              onTap: () => context.go('/doctor-dashboard'),
              sh: sh,
            ),
            _NavItem(
              icon: Icons.calendar_month_outlined,
              label: context.t('nav_appointments'),
              selected: _selected('/doctor-appointments'),
              onTap: () => context.go('/doctor-appointments'),
              sh: sh,
            ),
            _NavItem(
              icon: Icons.people_outline,
              label: context.t('nav_patients'),
              selected: _selected('/doctor-patients'),
              onTap: () => context.go('/doctor-patients'),
              sh: sh,
            ),
            _NavItem(
              icon: Icons.person_outline,
              label: context.t('profile'),
              selected: _selected('/doctor-profile'),
              onTap: () => context.go('/doctor-profile'),
              sh: sh,
            ),
            _NavItem(
              icon: Icons.chat_outlined,
              label: context.t('nav_chat'),
              selected: _selected('/chat-list'),
              onTap: () => context.go('/chat-list'),
              sh: sh,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.sh,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final SafeHairColors sh;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 36,
              decoration: BoxDecoration(
                color: selected ? sh.selectedNavBg : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 20,
                color: selected ? sh.selectedNavFg : sh.unselectedNavFg,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? sh.textPrimary : sh.unselectedNavFg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
