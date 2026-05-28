import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import '../utils/scalp_api_normalize.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  ApiService._internal();
  static const String _v1 = '/api/v1';
  String? _accessToken;
  String? _currentUserId;
  String? _currentUserEmail;

  /// Web / desktop: localhost (or page host on LAN). Android emulator: 10.0.2.2. Real device: `--dart-define`.
  String get _baseUrl => ApiConfig.resolveBaseUrl();

  /// Clears JWT and user headers (call on sign-out so the next user does not reuse the session).
  void clearSession() {
    _accessToken = null;
    _currentUserId = null;
    _currentUserEmail = null;
  }

  /// After Firebase Auth sign-in/sign-up, attach uid/email so [registerDoctor] and other calls send [X-User-Id] headers.
  void attachUserContext({required String userId, required String email}) {
    _currentUserId = userId;
    _currentUserEmail = email;
  }

  Map<String, String> _jsonHeaders({bool withAuth = false}) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (withAuth && _accessToken != null && _accessToken!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_accessToken';
    }
    if (_currentUserId != null && _currentUserId!.isNotEmpty) {
      h['X-User-Id'] = _currentUserId!;
    }
    if (_currentUserEmail != null && _currentUserEmail!.isNotEmpty) {
      h['X-User-Email'] = _currentUserEmail!;
    }
    return h;
  }

  String? get currentUserId => _currentUserId;

  Future<List<dynamic>> getDoctors() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl$_v1/doctors/verified'));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body is Map<String, dynamic>) {
          return List<dynamic>.from(body['doctors'] ?? const []);
        }
        if (body is List) return body;
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> register({
    required String email,
    required String password,
    required String role,
    String? name,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl$_v1/auth/register'),
        headers: _jsonHeaders(),
        body: jsonEncode({
          'email': email,
          'password': password,
          'role': role,
          if (name != null) 'name': name,
        }),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      if (res.statusCode == 409) {
        return {
          'success': false,
          'error': 'email-already-in-use',
          'detail': 'Email already registered',
        };
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl$_v1/auth/login'),
        headers: _jsonHeaders(),
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (res.statusCode == 200) {
        final m = jsonDecode(res.body) as Map<String, dynamic>;
        _accessToken = m['access_token']?.toString();
        final u = (m['user'] is Map<String, dynamic>) ? (m['user'] as Map<String, dynamic>) : <String, dynamic>{};
        _currentUserId = u['id']?.toString();
        _currentUserEmail = u['email']?.toString() ?? email;
        return m;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> forgotPassword(String email) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl$_v1/auth/forgot-password'),
        headers: _jsonHeaders(),
        body: jsonEncode({'email': email}),
      );
      return res.statusCode == 200;
    } catch (_) {}
    return false;
  }

  Future<bool> verifyOtp({required String email, required String otp}) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl$_v1/auth/verify-otp'),
        headers: _jsonHeaders(),
        body: jsonEncode({'email': email, 'otp': otp}),
      );
      return res.statusCode == 200;
    } catch (_) {}
    return false;
  }

  Future<Map<String, dynamic>?> getMyProfile({String? userId}) async {
    try {
      final uid = userId ?? _currentUserId;
      final q = (uid == null || uid.isEmpty) ? '' : '?user_id=$uid';
      final res = await http.get(
        Uri.parse('$_baseUrl$_v1/users/me$q'),
        headers: _jsonHeaders(withAuth: true),
      );
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> updateMyProfile(Map<String, dynamic> payload, {String? userId}) async {
    try {
      final uid = userId ?? _currentUserId;
      final q = (uid == null || uid.isEmpty) ? '' : '?user_id=$uid';
      final res = await http.put(
        Uri.parse('$_baseUrl$_v1/users/me$q'),
        headers: _jsonHeaders(withAuth: true),
        body: jsonEncode(payload),
      );
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> analyzeScalpImage(
    List<int> imageBytes, {
    String? userId,
    String? patientGender,
    int? patientAge,
  }) async {
    try {
      // Preferred v1 route: report upload + analysis.
      final uid = userId ?? _currentUserId;
      final v1 = await uploadReportImage(
        imageBytes: imageBytes,
        userId: uid ?? 'unknown',
        patientGender: patientGender,
        patientAge: patientAge,
      );
      if (v1 != null && (v1['analysis'] != null || v1['hair_strength'] != null)) {
        return normalizeScalpApiResponse(v1);
      }

      // Direct AI route (trained OpenCV + ONNX + joblib on backend).
      final base64Image = base64Encode(imageBytes);
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/ai/scalp-analyze'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'image_base64': base64Image,
              if (patientGender != null && patientGender.trim().isNotEmpty)
                'patient_gender': patientGender.trim(),
              if (patientAge != null && patientAge > 0 && patientAge < 120) 'patient_age': patientAge,
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body is Map<String, dynamic>) {
          if (body['success'] == true) {
            return normalizeScalpApiResponse(Map<String, dynamic>.from(body)..remove('success'));
          }
          return normalizeScalpApiResponse(Map<String, dynamic>.from(body));
        }
      }

      if (!await isBackendReachable()) {
        return {
          '_error':
              'AI backend is not reachable at $_baseUrl. ${ApiConfig.connectionHelp(_baseUrl)}',
        };
      }
      return {'_error': 'AI API failed (${res.statusCode}): ${res.body}'};
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('Failed to fetch') || msg.contains('Connection refused') || msg.contains('SocketException')) {
        return {
          '_error':
              'Cannot reach AI server at $_baseUrl. ${ApiConfig.connectionHelp(_baseUrl)}',
        };
      }
      return {'_error': 'AI API request error: $e'};
    }
  }

  /// True when FastAPI responds (e.g. before scalp analyze).
  Future<bool> isBackendReachable() async {
    final status = await getAiStatus();
    return status != null;
  }

  Future<Map<String, dynamic>?> getAiStatus() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/api/ai/status')).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> createAppointment({
    required String userId,
    required String doctorId,
    required String doctorName,
    required String date,
    required String timeSlot,
    required int reminderMinutes,
    String? consultationNotes,
    String? patientName,
    String? priority,
  }) async {
    try {
      final consult = await http.post(
        Uri.parse('$_baseUrl$_v1/consultations/request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'doctor_id': doctorId,
          'note': consultationNotes ?? '$date $timeSlot',
        }),
      );
      if (consult.statusCode == 200) return jsonDecode(consult.body) as Map<String, dynamic>;
      // Fallback to legacy endpoint for backward compatibility.
      final legacy = await http.post(
        Uri.parse('$_baseUrl/api/appointments'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'doctor_id': doctorId,
          'doctor_name': doctorName,
          'date': date,
          'time_slot': timeSlot,
          'reminder_minutes': reminderMinutes,
          'consultation_notes': consultationNotes,
          if (patientName != null && patientName.isNotEmpty) 'patient_name': patientName,
          if (priority == 'urgent') 'priority': priority,
        }),
      );
      if (legacy.statusCode == 200) return jsonDecode(legacy.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<bool> savePatientDetails(Map<String, dynamic> data) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/patient-details'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      return res.statusCode == 200;
    } catch (_) {}
    return false;
  }

  Future<List<dynamic>> getGuidelines({String? category}) async {
    try {
      var url = '$_baseUrl/api/guidelines';
      if (category != null) url += '?category=$category';
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) return jsonDecode(res.body) as List;
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> saveScalpAnalysis(Map<String, dynamic> data) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/scalp-analysis'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> saveReport(Map<String, dynamic> data) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/reports'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> uploadReportImage({
    required List<int> imageBytes,
    required String userId,
    String filename = 'scalp.jpg',
    String? patientGender,
    int? patientAge,
  }) async {
    try {
      final qp = <String, String>{
        'user_id': userId,
        if (patientGender != null && patientGender.trim().isNotEmpty) 'patient_gender': patientGender.trim(),
        if (patientAge != null && patientAge > 0 && patientAge < 120) 'patient_age': '$patientAge',
      };
      final uri = Uri.parse('$_baseUrl$_v1/reports/upload').replace(queryParameters: qp);
      final req = http.MultipartRequest('POST', uri);
      req.files.add(http.MultipartFile.fromBytes('file', imageBytes, filename: filename));
      req.headers.addAll(_jsonHeaders(withAuth: true)..remove('Content-Type'));
      final streamed = await req.send();
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode == 200) return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<List<dynamic>> getMyReports({String? userId}) async {
    try {
      final uid = userId ?? _currentUserId;
      final q = (uid == null || uid.isEmpty) ? '' : '?user_id=$uid';
      final res = await http.get(
        Uri.parse('$_baseUrl$_v1/reports/my$q'),
        headers: _jsonHeaders(withAuth: true),
      );
      if (res.statusCode == 200) {
        final m = jsonDecode(res.body) as Map<String, dynamic>;
        return List<dynamic>.from(m['reports'] ?? const []);
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> getReportById(String reportId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl$_v1/reports/$reportId'),
        headers: _jsonHeaders(withAuth: true),
      );
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static const Duration _registerDoctorTimeout = Duration(seconds: 25);

  Future<Map<String, dynamic>?> registerDoctor(Map<String, dynamic> payload) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl$_v1/doctors/register'),
            headers: _jsonHeaders(withAuth: true),
            body: jsonEncode(payload),
          )
          .timeout(_registerDoctorTimeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      if (kDebugMode) {
        // ignore: avoid_print
        print('registerDoctor failed: ${res.statusCode} ${res.body}');
      }
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('registerDoctor error: $e\n$st');
      }
    }
    return null;
  }

  Future<List<dynamic>> getMyConsultations({String? userId, String? doctorId}) async {
    try {
      final qp = <String>[];
      if (userId != null && userId.isNotEmpty) qp.add('user_id=$userId');
      if (doctorId != null && doctorId.isNotEmpty) qp.add('doctor_id=$doctorId');
      final q = qp.isEmpty ? '' : '?${qp.join('&')}';
      final res = await http.get(
        Uri.parse('$_baseUrl$_v1/consultations/my$q'),
        headers: _jsonHeaders(withAuth: true),
      );
      if (res.statusCode == 200) {
        final m = jsonDecode(res.body) as Map<String, dynamic>;
        return List<dynamic>.from(m['consultations'] ?? const []);
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> respondConsultation({
    required String consultationId,
    required String doctorId,
    required String action,
    String? responseNote,
  }) async {
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl$_v1/consultations/$consultationId/respond'),
        headers: _jsonHeaders(withAuth: true),
        body: jsonEncode({
          'doctor_id': doctorId,
          'action': action,
          if (responseNote != null) 'response_note': responseNote,
        }),
      );
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }
}
