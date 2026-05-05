import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_colors.dart';
import '../providers/theme_provider.dart';

/// Pill-shaped light / dark switch with sun & moon icons so the control is obvious and tappable.
class ThemeToggleControl extends StatelessWidget {
  const ThemeToggleControl({super.key});

  static const Color _accent = Color(0xFF7B61FF);

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white54 : AppColors.textGrey;

    return Tooltip(
      message: theme.isDark ? 'Switch to light theme' : 'Switch to dark theme',
      child: Material(
        color: isDark ? const Color(0xFF2C3648) : const Color(0xFFE8EAED),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.light_mode_rounded,
                size: 18,
                color: theme.isDark ? muted : _accent,
              ),
              Transform.scale(
                scale: 0.9,
                child: Switch(
                  value: theme.isDark,
                  onChanged: (_) => context.read<ThemeProvider>().toggleTheme(),
                  activeThumbColor: _accent,
                  activeTrackColor: _accent.withValues(alpha: 0.45),
                  inactiveThumbColor: isDark ? Colors.white38 : Colors.white,
                  inactiveTrackColor: isDark ? Colors.white24 : Colors.black26,
                ),
              ),
              Icon(
                Icons.dark_mode_rounded,
                size: 18,
                color: theme.isDark ? _accent : muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
