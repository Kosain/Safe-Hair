class AppConstantsV2 {
  static const String appName = 'Safe Hair';
  static const String apiV1 = '/api/v1';

  static const String _webDefault = 'http://localhost:8000';
  static const String _mobileDefault = 'http://10.0.2.2:8000';

  static String get apiBaseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) {
      return override.endsWith('/') ? override.substring(0, override.length - 1) : override;
    }
    return _webDefault;
  }

  static String get mobileApiBaseUrl {
    const override = String.fromEnvironment('API_BASE_URL_MOBILE');
    if (override.isNotEmpty) {
      return override.endsWith('/') ? override.substring(0, override.length - 1) : override;
    }
    return _mobileDefault;
  }
}
