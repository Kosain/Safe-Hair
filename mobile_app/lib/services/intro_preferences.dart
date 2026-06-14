import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether the user has completed the app introduction screens.
class IntroPreferences {
  IntroPreferences._();

  static const String _prefKey = 'safe_hair_intro_seen';

  static Future<bool> hasSeenIntro() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markIntroSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, true);
    } catch (_) {}
  }
}
