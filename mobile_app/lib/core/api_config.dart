import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

import 'constants.dart';

/// Resolves FastAPI base URL for all HTTP clients (ApiService, Dio, etc.).
class ApiConfig {
  ApiConfig._();

  static const int backendPort = 8000;

  /// `flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000`
  static String get _dartDefineOverride {
    const raw = String.fromEnvironment('API_BASE_URL');
    if (raw.isEmpty) return '';
    var b = raw.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    return b;
  }

  /// Local LAN dev (http://192.168.x.x:8080) → backend on :8000.
  /// Production (Vercel, Firebase Hosting, etc.) → same origin, no custom port.
  static String _webBaseFromPageOrigin() {
    if (!kIsWeb) return AppConstants.apiBaseUrlWeb;
    final uri = Uri.base;
    final host = uri.host;
    if (host.isEmpty || host == 'localhost' || host == '127.0.0.1') {
      return AppConstants.apiBaseUrlWeb;
    }
    final scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
    const standardPorts = {80, 443};
    if (!uri.hasPort || standardPorts.contains(uri.port)) {
      return '$scheme://$host';
    }
    return '$scheme://$host:$backendPort';
  }

  static String resolveBaseUrl() {
    final override = _dartDefineOverride;
    if (override.isNotEmpty) return override;

    if (kIsWeb) return _webBaseFromPageOrigin();

    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppConstants.apiBaseUrlWeb;
    }

    // Android emulator → host machine. Real phone needs --dart-define=API_BASE_URL=...
    return AppConstants.apiBaseUrlMobile;
  }

  static bool isLocalhostUrl(String url) =>
      url.contains('localhost') || url.contains('127.0.0.1');

  static bool isEmulatorHost(String url) => url.contains('10.0.2.2');

  /// User-facing hint when analyze fails with "Failed to fetch".
  static String connectionHelp(String baseUrl) {
    if (kIsWeb) {
      if (isLocalhostUrl(baseUrl)) {
        return 'Start the AI backend on this PC: run backend\\start_backend.bat '
            '(http://localhost:8000), then try again.';
      }
      if (!isLocalhostUrl(baseUrl) && !baseUrl.contains(':$backendPort')) {
        return 'The AI backend may be offline or API_BASE_URL is misconfigured. '
            'This app is using $baseUrl — check your Vercel environment variables.';
      }
      return 'Start the AI backend on your PC (backend\\start_backend.bat) so it listens on '
          '0.0.0.0:8000 on the same Wi‑Fi. This app is using $baseUrl.';
    }
    if (isEmulatorHost(baseUrl)) {
      return 'On a real phone, run the app with:\n'
          'flutter run --dart-define=API_BASE_URL=http://YOUR_PC_IP:8000\n'
          '(same Wi‑Fi as the PC running start_backend.bat).';
    }
    return 'Start backend\\start_backend.bat on your PC and ensure the phone uses '
        'http://YOUR_PC_IP:8000 (not localhost). Current URL: $baseUrl';
  }
}
