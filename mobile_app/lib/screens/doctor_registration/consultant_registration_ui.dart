import 'package:flutter/material.dart';

import '../../core/app_colors.dart';

/// Black primary actions for consultant registration (per product spec).
ButtonStyle consultantPrimaryButtonStyle() {
  return FilledButton.styleFrom(
    backgroundColor: Colors.black,
    foregroundColor: Colors.white,
    minimumSize: const Size(double.infinity, 54),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
    elevation: 0,
  );
}

/// Smaller black pills for Camera / Upload-Gallery on step 1 (single row on narrow widths).
ButtonStyle consultantPhotoPickButtonStyle() {
  return FilledButton.styleFrom(
    backgroundColor: Colors.black,
    foregroundColor: Colors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
  );
}

BoxDecoration consultantCardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ],
  );
}

InputDecoration consultantInputDecoration({
  required String label,
  String? hint,
  String? errorText,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    errorText: errorText,
    filled: true,
    fillColor: Colors.white,
    labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.85), fontWeight: FontWeight.w600, fontSize: 13),
    floatingLabelStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 13),
    hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
    helperStyle: const TextStyle(color: Colors.black),
    prefixStyle: const TextStyle(color: Colors.black),
    suffixStyle: const TextStyle(color: Colors.black),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFF8D8D8D), width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFF1A1A1A), width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
    ),
  );
}
