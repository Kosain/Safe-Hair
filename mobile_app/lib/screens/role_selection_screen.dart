import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/app_colors.dart';
import '../core/responsive.dart';
import '../providers/auth_provider.dart';
import '../widgets/animated_primary_button.dart';
import '../widgets/firebase_init_banner.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

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
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 24, vertical: 32),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: cardMaxW),
                    child: Column(
                      children: [
                        const FirebaseInitBanner(),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.fromLTRB(28, 36, 28, 32),
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
                                color: const Color(0xFF2D7D4A).withValues(alpha: 0.06),
                                blurRadius: 0,
                                spreadRadius: 0,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGreen,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.darkButton.withValues(alpha: 0.12),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: const Image(
                                  image: AssetImage('assets/logo.png'),
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'SAFE HAIR',
                                style: TextStyle(
                                  fontSize: isWide ? 36 : 32,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textDark,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Hair & scalp care, guided by AI',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.4,
                                  color: AppColors.textGrey.withValues(alpha: 0.95),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 28),
                              Text(
                                'Who is using Safe Hair?',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: isWide ? 22 : 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Choose your role',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textGrey,
                                ),
                              ),
                              const SizedBox(height: 28),
                              Row(
                                children: [
                                  Expanded(
                                    child: _RoleHintChip(icon: Icons.auto_awesome, label: 'AI analysis'),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _RoleHintChip(icon: Icons.medical_services_outlined, label: 'Doctor access'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 28),
                              SizedBox(
                                width: double.infinity,
                                child: AnimatedPrimaryButton(
                                  onPressed: () {
                                    context.read<AuthProvider>().setRole('patient');
                                    context.go('/login/patient');
                                  },
                                  height: 54,
                                  borderRadius: 16,
                                  gradientColors: const [
                                    Color(0xFF2D2D2D),
                                    Color(0xFF1A1A1A),
                                  ],
                                  child: const Text(
                                    'Continue as Patient',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: OutlinedButton(
                                  onPressed: () {
                                    context.read<AuthProvider>().setRole('doctor');
                                    context.go('/login/doctor');
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.textDark,
                                    side: BorderSide(color: AppColors.darkButton.withValues(alpha: 0.35), width: 1.5),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Text(
                                    'Continue as Doctor',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Secure sign-in · Your data stays private',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textGrey.withValues(alpha: 0.85),
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
      ),
    );
  }
}

class _RoleHintChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _RoleHintChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: AppColors.darkButton.withValues(alpha: 0.85)),
          const SizedBox(width: 6),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
