import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/locale_provider.dart';
import 'app_translations.dart';

extension Tr on BuildContext {
  String t(String key) {
    final code = read<LocaleProvider>().languageCode;
    return AppTranslations.get(code, key);
  }
}
