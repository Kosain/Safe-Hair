import '../api_config.dart';

class AppConstantsV2 {
  static const String appName = 'Safe Hair';
  static const String apiV1 = '/api/v1';

  /// Same resolution as [ApiService] (web LAN host, dart-define, emulator, etc.).
  static String get apiBaseUrl => ApiConfig.resolveBaseUrl();
}
