import 'package:flutter/material.dart';

import '../core/app_colors.dart';

class GateScreen extends StatelessWidget {
  const GateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryGreen,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 24),
                CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.darkButton,
                  backgroundColor: AppColors.darkButton.withValues(alpha: 0.12),
                ),
                const SizedBox(height: 16),
                Text(
                  'Checking your account...',
                  style: TextStyle(fontSize: 16, color: AppColors.textDark),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

