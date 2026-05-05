/// API base URL for FastAPI backend.
/// - Web / same machine: use localhost.
/// - Android emulator: use 10.0.2.2 (emulator's host).
/// - Real Android device: use your PC's IP on same WiFi (e.g. http://192.168.1.5:8000).
///
/// Override: `flutter run --dart-define=API_BASE_URL=http://YOUR_IP:8000`
class AppConstants {
  /// Used when running on web (Chrome, etc.). Same machine as backend.
  static const String apiBaseUrlWeb = 'http://localhost:8000';

  /// Used when running on Android/iOS. Use 10.0.2.2 for emulator; for real device set your PC IP.
  static const String apiBaseUrlMobile = 'http://10.0.2.2:8000';

  /// Default base URL (used by ApiService with platform detection).
  static const String apiBaseUrl = apiBaseUrlWeb;
  static const List<String> timeSlots = [
    '10:00 AM', '12:00 PM', '02:00 PM', '03:00 PM', '05:00 PM'
  ];
  static const List<String> reminderOptions = [
    '20 Min', '25 Min', '30 Min', '35 Min', '40 Min'
  ];
  static const List<String> primaryConcerns = [
    'Hair loss', 'Dandruff', 'Allergy', 'Hair Thinning', 'Hair whitening', 'Others'
  ];
  static const List<String> durationOptions = [
    'Less than 6 months', '6-12 months', 'More than 1 year'
  ];
  static const List<String> previousTreatments = [
    'Medicines', 'Oils', 'Others', 'None'
  ];
  static const List<String> scalpConditions = [
    'Oily', 'Dry', 'Normal', 'Sensitive'
  ];

  /// Suggested medical qualifications (clinic signup, onboarding, etc.).
  static const List<String> doctorQualificationSuggestions = [
    'MBBS',
    'FCPS',
    'MD',
    'MCPS',
    'D.Derm',
    'M.Sc.',
    'MRCP',
  ];
}
