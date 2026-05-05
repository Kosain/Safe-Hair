import 'package:flutter/material.dart';

/// Breakpoints and responsive helpers for web + app
class Responsive {
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobileBreakpoint;

  static bool isTabletOrDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= mobileBreakpoint;

  static double widthOf(BuildContext context) => MediaQuery.sizeOf(context).width;

  /// Horizontal padding: larger on web/tablet
  static double horizontalPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= tabletBreakpoint) return 48;
    if (w >= mobileBreakpoint) return 32;
    return 24;
  }

  /// Max content width for web (centered layout)
  static double? maxContentWidth(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= tabletBreakpoint) return 500;
    return null;
  }

  /// Responsive font scale
  static double titleFontSize(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= tabletBreakpoint) return 32;
    return 28;
  }
}
