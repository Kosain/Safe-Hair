import 'package:flutter/material.dart';

import '../core/safe_hair_colors.dart';
import '../l10n/tr.dart';

/// Simple list picker for language / theme (no layout changes elsewhere).
Future<String?> showPreferencePickerDialog({
  required BuildContext context,
  required String titleKey,
  required List<(String value, String labelKey)> options,
  required String currentValue,
}) {
  final sh = context.sh;
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: sh.card,
        title: Text(
          ctx.t(titleKey),
          style: TextStyle(color: sh.textPrimary, fontWeight: FontWeight.w600, fontSize: 19),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((opt) {
            final selected = opt.$1 == currentValue;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                ctx.t(opt.$2),
                style: TextStyle(
                  color: sh.textPrimary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 16,
                ),
              ),
              trailing: selected ? Icon(Icons.check, color: sh.textPrimary) : null,
              onTap: () => Navigator.of(ctx).pop(opt.$1),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.t('cancel'), style: TextStyle(color: sh.textSecondary)),
          ),
        ],
      );
    },
  );
}
