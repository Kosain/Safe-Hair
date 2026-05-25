import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App locale (English / Urdu). Persisted locally.
/// TODO: migrate remaining screens to [context.t] keys in app_translations.dart.
class LocaleProvider extends ChangeNotifier {
  static const String _prefKey = 'safe_hair_locale';
  Locale _locale = const Locale('en');
  bool _initialized = false;

  Locale get locale => _locale;
  String get languageCode => _locale.languageCode;
  bool get isUrdu => _locale.languageCode == 'ur';
  bool get initialized => _initialized;

  LocaleProvider() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved == 'ur') {
        _locale = const Locale('ur');
      } else {
        _locale = const Locale('en');
      }
    } catch (_) {
      _locale = const Locale('en');
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    final code = locale.languageCode == 'ur' ? 'ur' : 'en';
    final next = Locale(code);
    if (_locale == next) return;
    _locale = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, code);
    } catch (_) {}
  }
}
