import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'safe_hair_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      extensions: const [SafeHairColors.light],
      colorScheme: ColorScheme.light(
        primary: AppColors.primaryGreen,
        surface: AppColors.primaryGreen,
        onPrimary: AppColors.textDark,
        onSurface: AppColors.textDark,
      ),
      scaffoldBackgroundColor: AppColors.primaryGreen,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textDark),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkButton,
          foregroundColor: AppColors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.darkButton,
        selectionColor: AppColors.darkButton.withValues(alpha: 0.28),
        selectionHandleColor: AppColors.darkButton,
      ),
      // Primary is pale green for branding; default progress indicators use
      // colorScheme.primary and would be invisible on gate / green scaffolds.
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.darkButton,
        circularTrackColor: Color(0x332D2D2D),
      ),
    );
  }

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      brightness: Brightness.dark,
      extensions: const [SafeHairColors.dark],
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFE0E0E0),
        onPrimary: Colors.black,
        surface: Color(0xFF1C2129),
        onSurface: Colors.white,
      ),
      scaffoldBackgroundColor: SafeHairColors.dark.scaffold,
      cardColor: SafeHairColors.dark.card,
      dividerColor: SafeHairColors.dark.border,
      appBarTheme: AppBarTheme(
        backgroundColor: SafeHairColors.dark.appBar,
        foregroundColor: SafeHairColors.dark.textPrimary,
        elevation: 0,
        iconTheme: IconThemeData(color: SafeHairColors.dark.textPrimary),
      ),
      dialogTheme: DialogThemeData(backgroundColor: SafeHairColors.dark.card),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: SafeHairColors.dark.card,
        contentTextStyle: TextStyle(color: SafeHairColors.dark.textPrimary),
      ),
      listTileTheme: ListTileThemeData(
        textColor: SafeHairColors.dark.textPrimary,
        iconColor: SafeHairColors.dark.icon,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1B2230),
        labelStyle: TextStyle(color: SafeHairColors.dark.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: SafeHairColors.dark.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Color(0xFF64D3FF),
        selectionColor: Color(0x5564D3FF),
        selectionHandleColor: Color(0xFF64D3FF),
      ),
    );
  }
}
