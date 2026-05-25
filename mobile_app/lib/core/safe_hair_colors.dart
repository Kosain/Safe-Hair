import 'package:flutter/material.dart';

/// Theme-aware black/white palette for main shells (light ↔ dark).
class SafeHairColors extends ThemeExtension<SafeHairColors> {
  const SafeHairColors({
    required this.scaffold,
    required this.card,
    required this.navBar,
    required this.textPrimary,
    required this.textSecondary,
    required this.icon,
    required this.border,
    required this.selectedNavBg,
    required this.selectedNavFg,
    required this.unselectedNavFg,
    required this.sidebarSelectedBg,
    required this.appBar,
  });

  final Color scaffold;
  final Color card;
  final Color navBar;
  final Color textPrimary;
  final Color textSecondary;
  final Color icon;
  final Color border;
  final Color selectedNavBg;
  final Color selectedNavFg;
  final Color unselectedNavFg;
  final Color sidebarSelectedBg;
  final Color appBar;

  static const light = SafeHairColors(
    scaffold: Color(0xFFF4F6F8),
    card: Colors.white,
    navBar: Colors.white,
    textPrimary: Colors.black,
    textSecondary: Color(0xFF666666),
    icon: Color(0xDE000000),
    border: Color(0xFFE0E0E0),
    selectedNavBg: Color(0xFF151515),
    selectedNavFg: Colors.white,
    unselectedNavFg: Color(0xFF757575),
    sidebarSelectedBg: Color(0xFFF0F0F0),
    appBar: Colors.white,
  );

  static const dark = SafeHairColors(
    scaffold: Color(0xFF10131A),
    card: Color(0xFF1C2129),
    navBar: Color(0xFF171B24),
    textPrimary: Colors.white,
    textSecondary: Color(0xFFB0B0B0),
    icon: Color(0xE6FFFFFF),
    border: Color(0xFF2E3540),
    selectedNavBg: Colors.white,
    selectedNavFg: Colors.black,
    unselectedNavFg: Color(0xFF9E9E9E),
    sidebarSelectedBg: Color(0xFF2A3038),
    appBar: Color(0xFF1C2129),
  );

  @override
  SafeHairColors copyWith({
    Color? scaffold,
    Color? card,
    Color? navBar,
    Color? textPrimary,
    Color? textSecondary,
    Color? icon,
    Color? border,
    Color? selectedNavBg,
    Color? selectedNavFg,
    Color? unselectedNavFg,
    Color? sidebarSelectedBg,
    Color? appBar,
  }) {
    return SafeHairColors(
      scaffold: scaffold ?? this.scaffold,
      card: card ?? this.card,
      navBar: navBar ?? this.navBar,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      icon: icon ?? this.icon,
      border: border ?? this.border,
      selectedNavBg: selectedNavBg ?? this.selectedNavBg,
      selectedNavFg: selectedNavFg ?? this.selectedNavFg,
      unselectedNavFg: unselectedNavFg ?? this.unselectedNavFg,
      sidebarSelectedBg: sidebarSelectedBg ?? this.sidebarSelectedBg,
      appBar: appBar ?? this.appBar,
    );
  }

  @override
  SafeHairColors lerp(ThemeExtension<SafeHairColors>? other, double t) {
    if (other is! SafeHairColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return SafeHairColors(
      scaffold: l(scaffold, other.scaffold),
      card: l(card, other.card),
      navBar: l(navBar, other.navBar),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      icon: l(icon, other.icon),
      border: l(border, other.border),
      selectedNavBg: l(selectedNavBg, other.selectedNavBg),
      selectedNavFg: l(selectedNavFg, other.selectedNavFg),
      unselectedNavFg: l(unselectedNavFg, other.unselectedNavFg),
      sidebarSelectedBg: l(sidebarSelectedBg, other.sidebarSelectedBg),
      appBar: l(appBar, other.appBar),
    );
  }
}

extension SafeHairColorsContext on BuildContext {
  SafeHairColors get sh => Theme.of(this).extension<SafeHairColors>() ?? SafeHairColors.light;
}
