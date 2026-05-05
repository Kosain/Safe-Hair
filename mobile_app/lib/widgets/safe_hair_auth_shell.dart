import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import 'package:go_router/go_router.dart';

import '../core/responsive.dart';

/// Gradient background + white card layout aligned with [RoleSelectionScreen].
class SafeHairAuthShell extends StatelessWidget {
  const SafeHairAuthShell({
    super.key,
    required this.title,
    this.subtitle,
    this.backTo = '/role',
    required this.body,
    this.footer,
    this.showLogo = true,
  });

  final String title;
  final String? subtitle;
  final String backTo;
  final Widget body;
  final Widget? footer;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isWide = w >= Responsive.tabletBreakpoint;
    final cardMaxW = isWide ? 440.0 : double.infinity;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF0FAF2),
              Color(0xFFE8F5E9),
              Color(0xFFDFF5E4),
            ],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -60,
              child: IgnorePointer(
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2D2D2D).withValues(alpha: 0.04),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 40,
              left: -40,
              child: IgnorePointer(
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4A90E2).withValues(alpha: 0.06),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Stack(
                children: [
                  Positioned(
                    top: 8,
                    left: 8,
                    child: IconButton(
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      onPressed: () => context.go(backTo),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textDark, size: 20),
                    ),
                  ),
                  Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(isWide ? 40 : 20, 56, isWide ? 40 : 20, 20),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: cardMaxW),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                          padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.07),
                                blurRadius: 32,
                                offset: const Offset(0, 12),
                              ),
                              BoxShadow(
                                color: const Color(0xFF2D7D4A).withValues(alpha: 0.05),
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showLogo) ...[
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryGreen,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.darkButton.withValues(alpha: 0.1),
                                          blurRadius: 14,
                                          offset: const Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: const Image(
                                      image: AssetImage('assets/logo.png'),
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                              ],
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textDark,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              if (subtitle != null && subtitle!.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  subtitle!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.45,
                                    color: AppColors.textGrey.withValues(alpha: 0.95),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 22),
                              body,
                            ],
                          ),
                        ),
                            if (footer != null) ...[
                              const SizedBox(height: 22),
                              footer!,
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration safeHairAuthInputDecoration({
  required String hint,
  Widget? suffixIcon,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(22),
    borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.18)),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.textGrey.withValues(alpha: 0.85), fontSize: 14),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: const BorderSide(color: AppColors.darkButton, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide(color: Colors.red.shade400, width: 1),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide(color: Colors.red.shade600, width: 1.2),
    ),
    suffixIcon: suffixIcon,
  );
}

/// Pill-shaped dark social buttons (Safe Hair style).
class AuthSocialButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Widget leading;
  final List<Color> gradientColors;
  final Color textColor;
  final List<BoxShadow> boxShadow;
  final BorderSide? borderSide;

  const AuthSocialButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.leading,
    this.gradientColors = const [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
    this.textColor = Colors.white,
    this.boxShadow = const [
      BoxShadow(
        color: Color(0x38000000),
        blurRadius: 14,
        offset: Offset(0, 6),
      ),
    ],
    this.borderSide,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.98, end: 1.0),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(colors: gradientColors),
            boxShadow: boxShadow,
            border: borderSide == null ? null : Border.fromBorderSide(borderSide!),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    leading,
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
