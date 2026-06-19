import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../core/demo_accounts.dart';
import '../firebase_options.dart';

class FirebaseService {
  static bool _initialized = false;
  static String? lastAuthError;
  static String? lastInitError;

  /// Merges `doctorId` and legacy `doctorID` matches without a Firestore OR query (avoids composite-index / web issues).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _appointmentDocsForDoctorMergedOnce(
    String doctorId,
  ) async {
    if (!_initialized || doctorId.isEmpty) return [];
    try {
      final a = await firestore.collection('appointments').where('doctorId', isEqualTo: doctorId).get();
      final b = await firestore.collection('appointments').where('doctorID', isEqualTo: doctorId).get();
      final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final d in a.docs) {
        byId[d.id] = d;
      }
      for (final d in b.docs) {
        byId[d.id] = d;
      }
      return byId.values.toList();
    } catch (e, st) {
      debugPrint('_appointmentDocsForDoctorMergedOnce: $e\n$st');
      return [];
    }
  }

  /// Cleared on each `savePatientDetails` call. Explains failure when result is null.
  static String? lastPatientSaveError;

  static bool get isInitialized => _initialized;

  /// For [debugPrint] when diagnosing Storage uploads (matches [Firebase.initializeApp] options).
  static String get debugProjectIdForLogs => DefaultFirebaseOptions.currentPlatform.projectId;

  /// Called once from `main.dart` after Firebase initialization completes.
  static void markInitialized() {
    _initialized = true;
    lastInitError = null;
    // Web networks (VPN/proxy/firewall) may block Firestore's default transport.
    // Auto-detect + long-polling fallback prevents repeated "backend didn't respond" timeouts.
    if (kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        webExperimentalAutoDetectLongPolling: true,
      );
      if (DefaultFirebaseOptions.web.appId.contains('placeholder') || DefaultFirebaseOptions.web.apiKey.isEmpty) {
        debugPrint('Firebase web configuration appears incomplete. Run `flutterfire configure` to set a real web appId.');
      }
    }
  }

  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;
  static FirebaseStorage get storage => FirebaseStorage.instance;

  /// Same bucket string as [Firebase.initializeApp] / native config (avoids default-instance drift).
  static FirebaseStorage _scopedStorage() {
    final raw = (Firebase.app().options.storageBucket ?? '').trim();
    if (raw.isEmpty) return FirebaseStorage.instance;
    final gs = raw.startsWith('gs://') ? raw : 'gs://$raw';
    return FirebaseStorage.instanceFor(app: Firebase.app(), bucket: gs);
  }

  static const int kMaxDoctorProfileImageBytes = 5 * 1024 * 1024;

  /// True only for JPEG or PNG magic bytes (excludes WebP, HEIC mis-detected as JPEG, etc.).
  static bool isDoctorProfileImageAllowedFormat(Uint8List bytes) {
    if (bytes.length < 3) return false;
    final isPng =
        bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
    return isPng || isJpeg;
  }

  /// Extension + content-type for doctor profile upload (call only after [isDoctorProfileImageAllowedFormat] is true).
  static ({String ext, String contentType}) doctorProfileImageType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return (ext: 'png', contentType: 'image/png');
    }
    return (ext: 'jpg', contentType: 'image/jpeg');
  }

  /// Refreshes ID token before Storage writes (avoids stale-auth edge cases during onboarding).
  static Future<void> refreshAuthTokenForUpload() async {
    try {
      await auth.currentUser?.getIdToken(true);
    } catch (_) {}
  }

  /// Detect image type from magic bytes so Storage [contentType] matches the payload (fixes wrong types from camera/gallery filenames).
  static ({String ext, String contentType}) sniffImageBytes(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return (ext: 'png', contentType: 'image/png');
    }
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return (ext: 'jpg', contentType: 'image/jpeg');
    }
    if (bytes.length >= 12) {
      final riff = String.fromCharCodes(bytes.sublist(0, 4));
      final webp = String.fromCharCodes(bytes.sublist(8, 12));
      if (riff == 'RIFF' && webp == 'WEBP') {
        return (ext: 'webp', contentType: 'image/webp');
      }
    }
    return (ext: 'jpg', contentType: 'image/jpeg');
  }

  static Future<String> _getDownloadUrlWithRetry(Reference ref) async {
    const maxAttempts = 16;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await ref.getDownloadURL().timeout(const Duration(seconds: 20));
      } catch (e) {
        final notFound = (e is FirebaseException && e.code == 'object-not-found') ||
            e.toString().toLowerCase().contains('object-not-found');
        if (notFound && attempt < maxAttempts - 1) {
          final shift = attempt < 11 ? attempt : 11;
          final ms = (200 * (1 << shift)).clamp(200, 4000).toInt();
          await Future<void>.delayed(Duration(milliseconds: ms));
          continue;
        }
        rethrow;
      }
    }
    throw StateError('_getDownloadUrlWithRetry: exhausted retries');
  }

  static String _newDownloadToken() {
    final r = Random();
    final a = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final b = r.nextInt(1 << 32).toRadixString(16);
    final c = r.nextInt(1 << 32).toRadixString(16);
    return '$a$b$c';
  }

  static String? _bucketHostName() {
    final raw = (Firebase.app().options.storageBucket ?? '').trim();
    if (raw.isEmpty) return null;
    return raw.replaceFirst('gs://', '');
  }

  static String? _manualDownloadUrl({
    required String bucket,
    required String fullPath,
    required String token,
  }) {
    if (bucket.isEmpty || fullPath.isEmpty || token.isEmpty) return null;
    final encoded = Uri.encodeComponent(fullPath);
    return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$encoded?alt=media&token=$token';
  }

  // ============ Auth ============
  static User? get currentUser => auth.currentUser;
  static Stream<User?> get authStateChanges => auth.authStateChanges();

  /// Re-initialize Firebase if the app started before options were ready (common on web hot restart).
  static Future<bool> ensureReady() async {
    if (_initialized) return true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }
      markInitialized();
      return true;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('duplicate-app') || msg.contains('[core/duplicate-app]')) {
        markInitialized();
        return true;
      }
      lastInitError = 'Firebase initialization failed: $e';
      debugPrint(lastInitError);
      return false;
    }
  }

  /// Verifies password against Firebase Auth REST (same project as [DefaultFirebaseOptions]).
  static Future<bool> _restEmailPasswordOk(String email, String password) async {
    try {
      final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
      final uri = Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey',
      );
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'password': password,
              'returnSecureToken': true,
            }),
          )
          .timeout(const Duration(seconds: 20));
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('_restEmailPasswordOk: $e');
      return false;
    }
  }

  static Future<UserCredential?> signInWithEmail(String email, String password) async {
    lastAuthError = null;
    if (!await ensureReady()) {
      lastAuthError = lastInitError ?? 'Firebase is not initialized on this app build.';
      return null;
    }
    final loginEmail = email.trim();
    try {
      return await auth.signInWithEmailAndPassword(email: loginEmail, password: password);
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase signInWithEmail error: code=${e.code} message=${e.message}');
      // Web SDK sometimes fails while REST accepts the same demo password — retry once.
      if (e.code == 'invalid-credential' ||
          e.code == 'wrong-password' ||
          e.code == 'user-not-found') {
        final restOk = await _restEmailPasswordOk(loginEmail, password);
        if (restOk) {
          try {
            await auth.signOut();
          } catch (_) {}
          try {
            return await auth.signInWithEmailAndPassword(email: loginEmail, password: password);
          } on FirebaseAuthException catch (e2) {
            debugPrint('signIn retry after REST ok: ${e2.code} ${e2.message}');
          }
          try {
            final cred = EmailAuthProvider.credential(email: loginEmail, password: password);
            return await auth.signInWithCredential(cred);
          } on FirebaseAuthException catch (e3) {
            debugPrint('signInWithCredential retry: ${e3.code} ${e3.message}');
          }
          lastAuthError =
              'Password is correct in Firebase but the app could not start a session. '
              'In Firebase Console → Authentication → Settings, add `localhost` and `127.0.0.1` under Authorized domains, '
              'then fully restart the app (not hot reload).';
          return null;
        }
        lastAuthError =
            'Invalid email or password. Demo accounts (case-sensitive): '
            'Patient $loginEmail / ${DemoAccounts.patientPassword} — '
            'Dr. Ayesha ${DemoAccounts.doctorRows.first.email} / ${DemoAccounts.doctorRows.first.password}';
      } else if (e.code == 'invalid-email') {
        lastAuthError = 'Please enter a valid email address.';
      } else if (e.code == 'user-disabled') {
        lastAuthError = 'This account has been disabled. Contact support.';
      } else if (e.code == 'network-request-failed') {
        lastAuthError = 'Check your internet connection and try again.';
      } else if (e.code == 'too-many-requests') {
        lastAuthError = 'Too many attempts. Please wait a moment and try again.';
      } else {
        lastAuthError = e.message ?? 'Login failed. Please try again.';
      }
    } catch (e, st) {
      debugPrint('signInWithEmail unexpected error: $e\n$st');
      lastAuthError = 'Login failed. Please try again.';
    }
    return null;
  }

  static Future<UserCredential?> signUpWithEmail(String email, String password) async {
    lastAuthError = null;
    if (!_initialized) {
      lastAuthError = lastInitError ?? 'Firebase is not initialized on this app build.';
      return null;
    }
    try {
      return await auth.createUserWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase signUpWithEmail error: code=${e.code} message=${e.message}');
      if (e.code == 'email-already-in-use') {
        lastAuthError = 'This email is already registered. Please login with this email.';
      } else if (e.code == 'weak-password') {
        lastAuthError = 'Password is too weak. Use at least 6 characters.';
      } else if (e.code == 'invalid-email') {
        lastAuthError = 'Please enter a valid email address.';
      } else if (e.code == 'network-request-failed') {
        lastAuthError = 'Check your internet connection and try again.';
      } else if (e.code == 'operation-not-allowed') {
        lastAuthError = 'Email/Password sign-in is disabled in Firebase Console.';
      } else if (e.code == 'too-many-requests') {
        lastAuthError = 'Too many attempts. Please wait a moment and try again.';
      } else {
        lastAuthError = e.message ?? 'Could not create account. Please try again.';
      }
    } catch (e, st) {
      debugPrint('signUpWithEmail unexpected error: $e\n$st');
      lastAuthError = 'Could not create account. Please try again.';
    }
    return null;
  }

  static Future<void> signOut() async {
    if (_initialized) await auth.signOut();
  }

  static Future<UserCredential?> signInWithGoogle() async {
    lastAuthError = null;
    if (!_initialized) {
      lastAuthError = lastInitError ?? 'Firebase is not initialized. Email/Google sign-in cannot run.';
      return null;
    }
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        provider.setCustomParameters({'prompt': 'select_account'});
        return await FirebaseService.auth.signInWithPopup(provider);
      }

      final googleSignIn = GoogleSignIn();
      final account = await googleSignIn.signIn();
      if (account == null) return null;
      final googleAuth = await account.authentication;
      final cred = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      return await FirebaseAuth.instance.signInWithCredential(cred);
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      lastAuthError = 'Google sign-in failed. On web, add this domain under Firebase Console → Authentication → Settings → Authorized domains. On Android, add SHA-256 to the app and download a fresh google-services.json.';
    }
    return null;
  }

  static Future<UserCredential?> signInWithFacebook() async {
    lastAuthError = null;
    if (!_initialized) {
      lastAuthError = lastInitError ?? 'Firebase is not initialized. Facebook sign-in cannot run.';
      return null;
    }
    try {
      if (kIsWeb) {
        final provider = FacebookAuthProvider();
        return await FirebaseAuth.instance.signInWithPopup(provider);
      }
      final result = await FacebookAuth.instance.login();
      if (result.status != LoginStatus.success || result.accessToken == null) return null;
      final cred = FacebookAuthProvider.credential(result.accessToken!.tokenString);
      return await FirebaseAuth.instance.signInWithCredential(cred);
    } catch (e) {
      debugPrint('Facebook sign-in failed: $e');
      lastAuthError = 'Facebook sign-in failed. Enable the Facebook provider in Firebase Console and add the OAuth redirect URL it shows for your platform.';
    }
    return null;
  }

  // ============ Doctors (separate collection) ============
  /// Cleared on each successful save; explains last failure for UI.
  static String? lastDoctorProfileSaveError;
  /// Set when patient "Book a doctor" list load fails or returns empty.
  static String? lastDoctorsListError;

  /// Returns `true` if the write succeeded (or was skipped because Firebase is off).
  static Future<bool> saveDoctorProfile(Map<String, dynamic> data) async {
    lastDoctorProfileSaveError = null;
    if (!_initialized) return false;
    try {
      final uid = data['userId'] ?? data['user_id'];
      if (uid == null) return false;
      await firestore.collection('doctors').doc(uid.toString()).set(data, SetOptions(merge: true));
      return true;
    } catch (e, st) {
      lastDoctorProfileSaveError = e.toString();
      debugPrint('saveDoctorProfile failed: $e\n$st');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getDoctorProfile(String userId) async {
    if (!_initialized) return null;
    try {
      final doc = await firestore.collection('doctors').doc(userId).get();
      if (doc.exists && doc.data() != null) {
        return doc.data();
      }
      // Legacy rows: document id ≠ Auth uid (re-seed or manual Console entry).
      final email = auth.currentUser?.email?.trim();
      if (email != null && email.isNotEmpty) {
        final byEmail = await firestore
            .collection('doctors')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (byEmail.docs.isNotEmpty) {
          final legacy = byEmail.docs.first;
          final data = Map<String, dynamic>.from(legacy.data());
          data['userId'] = userId;
          await firestore.collection('doctors').doc(userId).set(
            {
              ...data,
              'email': email,
              'profileCompleted': data['profileCompleted'] ?? true,
            },
            SetOptions(merge: true),
          );
          return data;
        }
      }
    } catch (e, st) {
      debugPrint('getDoctorProfile: $e\n$st');
    }
    return null;
  }

  /// Ensures `doctors/{uid}` exists for demo / returning doctors (FYP logins).
  static Future<bool> ensureDoctorProfileIfMissing({
    required String uid,
    required String email,
    String? displayName,
  }) async {
    if (!_initialized || uid.isEmpty) return false;
    final meta = DemoAccounts.doctorMeta(email);
    try {
      final existing = await firestore.collection('doctors').doc(uid).get();
      if (existing.exists) {
        final d = Map<String, dynamic>.from(existing.data() ?? {});
        final patch = <String, dynamic>{'userId': uid, 'email': email.trim()};
        if (d['profileCompleted'] == true || meta != null) {
          patch['profileCompleted'] = true;
          patch['bookable'] = true;
        }
        await firestore.collection('doctors').doc(uid).set(patch, SetOptions(merge: true));
        return true;
      }
      final byEmail = await firestore
          .collection('doctors')
          .where('email', isEqualTo: email.trim())
          .limit(1)
          .get();
      if (byEmail.docs.isNotEmpty) {
        final data = Map<String, dynamic>.from(byEmail.docs.first.data());
        data['userId'] = uid;
        data['email'] = email.trim();
        data['profileCompleted'] = true;
        await firestore.collection('doctors').doc(uid).set(data, SetOptions(merge: true));
        return true;
      }
      // Any signed-in doctor: ensure a starter row so patient booking can find them after onboarding.
      final display = (displayName ?? '').trim();
      final fallbackName = display.isNotEmpty ? display : email.split('@').first;
      await firestore.collection('doctors').doc(uid).set({
        'userId': uid,
        'role': 'doctor',
        'email': email.trim(),
        'fullName': fallbackName,
        'clinicName': 'Clinic',
        'city': '',
        'consultationFee': 0,
        'profileCompleted': false,
        'bookable': false,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      if (meta == null) return true;
      await firestore.collection('doctors').doc(uid).set({
        'userId': uid,
        'role': 'doctor',
        'email': email.trim(),
        'fullName': meta.fullName,
        'clinicName': 'Safe Hair Clinic',
        'city': 'Lahore',
        'consultationFee': 3000,
        'profileCompleted': true,
        'licenseNumber': 'DEMO-$uid',
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      return true;
    } catch (e, st) {
      debugPrint('ensureDoctorProfileIfMissing: $e\n$st');
      return false;
    }
  }

  /// New Firestore document id for `doctors/{id}` without writing a document yet.
  static String newDoctorRegistrationId() => firestore.collection('doctors').doc().id;

  /// Returns true if another doctor doc already uses this license number.
  static Future<bool> isDoctorLicenseNumberTaken(String licenseNumber) async {
    if (!_initialized) return false;
    final q = licenseNumber.trim();
    if (q.isEmpty) return false;
    try {
      final snap = await firestore
          .collection('doctors')
          .where('licenseNumber', isEqualTo: q)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (e, st) {
      debugPrint('isDoctorLicenseNumberTaken failed: $e\n$st');
      return false;
    }
  }

  /// Public doctor registration wizard (pre-auth). Uses [docId] as `doctors/{docId}`.
  static Future<bool> saveDoctorRegistration(String docId, Map<String, dynamic> data) async {
    lastDoctorProfileSaveError = null;
    if (!_initialized) return false;
    try {
      await firestore.collection('doctors').doc(docId).set(data, SetOptions(merge: true));
      return true;
    } catch (e, st) {
      lastDoctorProfileSaveError = e.toString();
      debugPrint('saveDoctorRegistration failed: $e\n$st');
      return false;
    }
  }

  /// Row map for booking lists. [id] is always the Firestore document id (`doctors/{uid}`) — same uid the doctor uses to sign in (seed + app use this).
  static Map<String, dynamic> _doctorRowFromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = Map<String, dynamic>.from(d.data() ?? {});
    data['id'] = d.id;
    data['firestoreDocId'] = d.id;
    return data;
  }

  /// True when a row is safe to show in patient booking (completed profile or enough display fields).
  static bool isBookableDoctorRow(Map<String, dynamic> data) {
    if (data['bookable'] == false) return false;
    if (data['profileCompleted'] == true) return true;
    final name = (data['fullName'] ?? data['name'] ?? '').toString().trim();
    final clinic = (data['clinicName'] ?? data['clinic_name'] ?? '').toString().trim();
    if (name.isNotEmpty && clinic.isNotEmpty) return true;
    final email = (data['email'] ?? '').toString().trim();
    return name.isNotEmpty && email.isNotEmpty;
  }

  static List<Map<String, dynamic>> _filterBookableDoctorRows(List<Map<String, dynamic>> rows) {
    final out = rows.where(isBookableDoctorRow).toList();
    out.sort((a, b) {
      final ac = a['profileCompleted'] == true ? 1 : 0;
      final bc = b['profileCompleted'] == true ? 1 : 0;
      if (ac != bc) return bc.compareTo(ac);
      return (a['fullName'] ?? '').toString().compareTo((b['fullName'] ?? '').toString());
    });
    _sortDoctorRowsForPicker(out);
    return out;
  }

  static Future<List<Map<String, dynamic>>> getVerifiedDoctorsOnce() async {
    if (!_initialized) return [];
    try {
      final snap = await firestore.collection('doctors').where('profileCompleted', isEqualTo: true).get();
      return _filterBookableDoctorRows(snap.docs.map(_doctorRowFromDoc).toList());
    } on FirebaseException catch (e) {
      debugPrint('getVerifiedDoctorsOnce: ${e.code} ${e.message}');
    } catch (e, st) {
      debugPrint('getVerifiedDoctorsOnce: $e\n$st');
    }
    return [];
  }

  static int _intFromFirestoreField(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v == null) return 0;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static void _sortDoctorRowsForPicker(List<Map<String, dynamic>> rows) {
    rows.sort((a, b) {
      final ac = _intFromFirestoreField(a, 'activeDoctorsCount');
      final bc = _intFromFirestoreField(b, 'activeDoctorsCount');
      return bc.compareTo(ac);
    });
  }

  /// Doctors this patient has booked before (when `doctors` collection is empty).
  static Future<List<Map<String, dynamic>>> getBookableDoctorsFromAppointmentHistory(String userId) async {
    if (!_initialized || userId.isEmpty) return [];
    try {
      final snap = await firestore.collection('appointments').where('userId', isEqualTo: userId).limit(50).get();
      final byId = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final id = (d['doctorId'] ?? d['doctor_id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        byId.putIfAbsent(
          id,
          () => {
            'id': id,
            'fullName': (d['doctorName'] ?? d['doctor_name'] ?? 'Doctor').toString(),
            'clinicName': (d['clinicName'] ?? d['clinic_name'] ?? 'Clinic').toString(),
            'city': (d['city'] ?? '').toString(),
            'consultationFee': d['consultationFee'] ?? d['consultation_fee'] ?? 0,
          },
        );
      }
      final rows = byId.values.toList();
      _sortDoctorRowsForPicker(rows);
      return rows;
    } catch (e, st) {
      debugPrint('getBookableDoctorsFromAppointmentHistory: $e\n$st');
    }
    return [];
  }

  /// For patient booking UIs. Uses verified doctors first; if none, any `doctors/{uid}` so [id] is always a real
  /// Firebase uid — never placeholder strings like `d1` or `1`, which would make the doctor dashboard query empty.
  static Future<List<Map<String, dynamic>>> getDoctorsForPatientBookingOnce({String? patientUserId}) async {
    lastDoctorsListError = null;
    if (!_initialized) {
      lastDoctorsListError = 'Firebase is not initialized.';
      return [];
    }
    try {
      final verified = await getVerifiedDoctorsOnce();
      if (verified.isNotEmpty) return verified;

      final snap = await firestore.collection('doctors').limit(100).get();
      final rows = _filterBookableDoctorRows(snap.docs.map(_doctorRowFromDoc).toList());
      if (rows.isNotEmpty) return rows;

      // Some builds only set role + email until onboarding finishes.
      try {
        final byRole = await firestore.collection('doctors').where('role', isEqualTo: 'doctor').limit(100).get();
        final roleRows = _filterBookableDoctorRows(byRole.docs.map(_doctorRowFromDoc).toList());
        if (roleRows.isNotEmpty) return roleRows;
      } on FirebaseException catch (e) {
        debugPrint('getDoctorsForPatientBookingOnce role query: ${e.code}');
      }

      if (patientUserId != null && patientUserId.isNotEmpty) {
        final fromHistory = await getBookableDoctorsFromAppointmentHistory(patientUserId);
        if (fromHistory.isNotEmpty) return fromHistory;
      }

      if (snap.docs.isEmpty) {
        lastDoctorsListError =
            'No doctor profiles in Firestore yet. Sign in as the doctor, complete all 6 registration steps, and save on the last step — then tap Refresh here.';
      } else {
        lastDoctorsListError =
            'Doctor profile(s) exist but are not bookable yet (finish registration: name, clinic, and save on step 6).';
      }
    } on FirebaseException catch (e) {
      debugPrint('getDoctorsForPatientBookingOnce: ${e.code} ${e.message}');
      lastDoctorsListError = e.code == 'permission-denied'
          ? 'Permission denied reading doctors. Deploy Firestore rules: firebase deploy --only firestore:rules'
          : 'Could not load doctors (${e.code}).';
      if (e.code == 'permission-denied' && patientUserId != null && patientUserId.isNotEmpty) {
        return getBookableDoctorsFromAppointmentHistory(patientUserId);
      }
    } catch (e, st) {
      debugPrint('getDoctorsForPatientBookingOnce: $e\n$st');
      lastDoctorsListError = 'Could not load doctors: $e';
    }
    return [];
  }

  /// Firestore documents must stay under ~1 MiB. Full scalp JPEGs as base64 exceed that on web.
  static Map<String, dynamic> slimReportPayloadForFirestore(Map<String, dynamic> payload) {
    const heavyKeys = {
      'sourceImageBase64',
      'analyzedImageBase64',
      'scalpImageBase64',
      'imageBase64',
      'overlay_image_base64',
      'overlayImageBase64',
    };
    final out = <String, dynamic>{};
    payload.forEach((k, v) {
      if (heavyKeys.contains(k)) return;
      if (k.endsWith('Base64') || k.endsWith('_base64')) return;
      out[k] = v;
    });
    final hasUrl = (out['scalpImageUrl'] ?? out['pdfUrl'] ?? '').toString().isNotEmpty;
    if (!hasUrl) {
      out['imagesStoredInStorage'] = false;
      out['note'] = 'Scalp photos are not stored in Firestore on localhost web; re-run scan to view overlay in-session.';
    }
    return out;
  }

  static Future<bool> isAppointmentSlotBooked({
    required String doctorId,
    required String date,
    required String timeSlot,
  }) async {
    if (!_initialized) return false;
    try {
      final docs = await _appointmentDocsForDoctorMergedOnce(doctorId);
      for (final doc in docs) {
        final data = doc.data();
        if ((data['date'] ?? '').toString() != date) continue;
        final ts = data['timeSlot'] ?? data['time_slot'];
        if (ts == null || ts.toString() != timeSlot) continue;
        final s = (data['status'] ?? 'confirmed').toString().toLowerCase();
        if (s == 'cancelled' || s == 'declined' || s == 'completed') continue;
        if (s == 'confirmed' || s == 'pending' || s.isEmpty) return true;
      }
      return false;
    } catch (_) {}
    return false;
  }

  /// Times already reserved for this doctor on this calendar date (excludes cancelled / declined / completed).
  /// Queries by [doctorId] only then filters by [date] client-side to avoid extra composite indexes.
  static Future<Set<String>> getBookedTimeSlotsForDoctorDate({
    required String doctorId,
    required String date,
  }) async {
    if (!_initialized) return {};
    try {
      final merged = await _appointmentDocsForDoctorMergedOnce(doctorId);
      final booked = <String>{};
      for (final doc in merged) {
        final data = doc.data();
        final docDate = (data['date'] ?? data['day'] ?? '').toString();
        if (docDate != date) continue;
        final s = (data['status'] ?? 'confirmed').toString().toLowerCase();
        if (s == 'cancelled' || s == 'declined' || s == 'completed') continue;
        final ts = data['timeSlot'] ?? data['time_slot'];
        if (ts != null && ts.toString().isNotEmpty) {
          booked.add(ts.toString());
        }
      }
      return booked;
    } catch (e, st) {
      debugPrint('getBookedTimeSlotsForDoctorDate: $e\n$st');
    }
    return {};
  }

  /// Live appointments for this doctor. Uses two equality listeners and merges by document id (no OR query).
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getAppointmentsForDoctor(String doctorId) {
    if (!_initialized || doctorId.isEmpty) {
      return Stream.value(const <QueryDocumentSnapshot<Map<String, dynamic>>>[]);
    }
    return Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.multi((controller) {
      QuerySnapshot<Map<String, dynamic>>? snapLower;
      QuerySnapshot<Map<String, dynamic>>? snapUpper;

      void emit() {
        final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        for (final d in snapLower?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
          byId[d.id] = d;
        }
        for (final d in snapUpper?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
          byId[d.id] = d;
        }
        controller.add(byId.values.toList());
      }

      final sub1 = firestore
          .collection('appointments')
          .where('doctorId', isEqualTo: doctorId)
          .snapshots()
          .listen(
        (s) {
          snapLower = s;
          emit();
        },
        onError: controller.addError,
      );
      final sub2 = firestore
          .collection('appointments')
          .where('doctorID', isEqualTo: doctorId)
          .snapshots()
          .listen(
        (s) {
          snapUpper = s;
          emit();
        },
        onError: controller.addError,
      );

      controller.onCancel = () {
        sub1.cancel();
        sub2.cancel();
      };
    });
  }

  // ============ Scalp Analyses ============
  static Future<String?> saveScalpAnalysis(Map<String, dynamic> data) async {
    if (!_initialized) return null;
    try {
      final doc = await firestore.collection('scalp_analyses').add({
        ...data,
        'createdAt': data['createdAt'] ?? DateTime.now().toIso8601String(),
      });
      return doc.id;
    } catch (_) {}
    return null;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getScalpAnalyses(String userId) {
    return firestore
        .collection('scalp_analyses')
        .where('userId', isEqualTo: userId)
        .snapshots();
  }

  static Future<bool> hasScalpAnalysis(String userId) async {
    if (!_initialized) return false;
    try {
      final snap = await firestore
          .collection('scalp_analyses')
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (_) {}
    return false;
  }

  static Future<Map<String, dynamic>?> getLatestScalpAnalysisOnce(String userId) async {
    if (!_initialized) return null;
    try {
      final snap = await firestore.collection('scalp_analyses').where('userId', isEqualTo: userId).get();
      if (snap.docs.isEmpty) return null;
      final docs = snap.docs.toList();
      docs.sort((a, b) {
        final ad = (a.data()['createdAt'] ?? '').toString();
        final bd = (b.data()['createdAt'] ?? '').toString();
        return bd.compareTo(ad);
      });
      return docs.first.data();
    } catch (_) {}
    return null;
  }

  // ============ Appointments ============
  static Future<String?> saveAppointment(Map<String, dynamic> data) async {
    if (!_initialized) return null;
    try {
      final merged = Map<String, dynamic>.from(data);
      final did = (merged['doctorId'] ?? merged['doctorID'])?.toString().trim();
      if (did == null || did.isEmpty) {
        debugPrint('saveAppointment: refused — missing doctorId/doctorID (booking would not show on any doctor).');
        return null;
      }
      merged['doctorId'] = did;
      merged['doctorID'] = did;
      final doc = await firestore.collection('appointments').add(merged);
      return doc.id;
    } catch (e, st) {
      debugPrint('saveAppointment failed: $e\n$st');
    }
    return null;
  }

  static Future<bool> updateAppointment(String docId, Map<String, dynamic> patch) async {
    if (!_initialized) return false;
    try {
      await firestore.collection('appointments').doc(docId).update({
        ...patch,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (_) {}
    return false;
  }

  static Future<bool> deleteAppointment(String docId) async {
    if (!_initialized) return false;
    try {
      await firestore.collection('appointments').doc(docId).delete();
      return true;
    } catch (_) {}
    return false;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getAppointments(String userId) {
    return firestore
        .collection('appointments')
        .where('userId', isEqualTo: userId)
        .snapshots();
  }

  /// One-shot patient appointments (userId + legacy patientId fields merged).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getPatientAppointmentsOnce(
    String userId,
  ) async {
    if (!_initialized || userId.isEmpty) return [];
    try {
      final a = await firestore.collection('appointments').where('userId', isEqualTo: userId).get();
      final b = await firestore.collection('appointments').where('patientId', isEqualTo: userId).get();
      final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final d in a.docs) {
        byId[d.id] = d;
      }
      for (final d in b.docs) {
        byId[d.id] = d;
      }
      return byId.values.toList();
    } catch (e, st) {
      debugPrint('getPatientAppointmentsOnce: $e\n$st');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getAppointmentOnce(String appointmentId) async {
    if (!_initialized || appointmentId.isEmpty) return null;
    try {
      final doc = await firestore.collection('appointments').doc(appointmentId).get();
      return doc.data();
    } catch (e, st) {
      debugPrint('getAppointmentOnce: $e\n$st');
      return null;
    }
  }

  /// Appointment ids from patient inbox rows where the doctor confirmed (top-level `event` / title).
  static Future<List<String>> getConfirmedAppointmentIdsForPatient(String userId) async {
    if (!_initialized || userId.isEmpty) return [];
    try {
      final snap = await firestore.collection('patient_notifications').where('userId', isEqualTo: userId).get();
      final ids = <String>[];
      for (final d in snap.docs) {
        final m = d.data();
        if ((m['type'] ?? 'appointment').toString() != 'appointment') continue;
        final event = (m['event'] ?? '').toString();
        final title = (m['title'] ?? '').toString().toLowerCase();
        if (event != 'confirmed' && !title.contains('confirmed')) continue;
        final apptId = (m['appointmentId'] ?? '').toString().trim();
        if (apptId.isNotEmpty) ids.add(apptId);
      }
      return ids;
    } catch (e, st) {
      debugPrint('getConfirmedAppointmentIdsForPatient: $e\n$st');
      return [];
    }
  }

  /// One-shot doctor appointments (merged doctorId + doctorID).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getDoctorAppointmentsOnce(
    String doctorId,
  ) async {
    return _appointmentDocsForDoctorMergedOnce(doctorId);
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getChatConversationsForPatientOnce(
    String patientId,
  ) async {
    if (!_initialized || patientId.isEmpty) return [];
    try {
      final snap = await firestore.collection('chat_conversations').where('patientId', isEqualTo: patientId).get();
      return snap.docs;
    } catch (e, st) {
      debugPrint('getChatConversationsForPatientOnce: $e\n$st');
      return [];
    }
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getChatConversationsForDoctorOnce(
    String doctorId,
  ) async {
    if (!_initialized || doctorId.isEmpty) return [];
    try {
      final snap = await firestore.collection('chat_conversations').where('doctorId', isEqualTo: doctorId).get();
      return snap.docs;
    } catch (e, st) {
      debugPrint('getChatConversationsForDoctorOnce: $e\n$st');
      return [];
    }
  }

  /// In-app inbox for patients (e.g. appointment accepted by doctor). Any signed-in user may create.
  static Future<String?> addPatientNotification({
    required String userId,
    required String title,
    required String body,
    String type = 'appointment',
    Map<String, dynamic>? extra,
  }) async {
    if (!_initialized) return null;
    try {
      final ref = await firestore.collection('patient_notifications').add({
        'userId': userId,
        'title': title,
        'body': body,
        'type': type,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        ...?extra,
      });
      return ref.id;
    } catch (e, st) {
      debugPrint('addPatientNotification: $e\n$st');
      return null;
    }
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> patientNotificationsStream(String userId) {
    return firestore.collection('patient_notifications').where('userId', isEqualTo: userId).snapshots();
  }

  static Future<bool> markPatientNotificationRead(String docId) async {
    if (!_initialized) return false;
    try {
      await firestore.collection('patient_notifications').doc(docId).update({'read': true});
      return true;
    } catch (e, st) {
      debugPrint('markPatientNotificationRead: $e\n$st');
      return false;
    }
  }

  /// Drops nulls, never stores base64 images in Firestore (use Storage URL only), trims long strings.
  static Map<String, dynamic> _sanitizePatientDetailsPayload(Map<String, dynamic> data) {
    const maxStr = 12000;
    final out = <String, dynamic>{};
    for (final e in data.entries) {
      if (e.value == null) continue;
      final k = e.key.toString();
      if (k == 'profileImageBase64' || k.toLowerCase().contains('base64')) {
        continue;
      }
      final v = e.value;
      if (v is String && v.length > maxStr) {
        out[k] = '${v.substring(0, maxStr)}…';
        continue;
      }
      out[k] = v;
    }
    return out;
  }

  // ============ Patient Details ============
  static Future<String?> savePatientDetails(Map<String, dynamic> data) async {
    lastPatientSaveError = null;
    if (!_initialized) {
      lastPatientSaveError = 'Firebase is not initialized.';
      return null;
    }
    final authUid = auth.currentUser?.uid;
    if (authUid == null || authUid.isEmpty) {
      lastPatientSaveError = 'You are not signed in. Log in again, then continue.';
      return null;
    }

    try {
      await auth.currentUser?.getIdToken(true);
    } catch (_) {}

    Map<String, dynamic> buildPayload(Map<String, dynamic> raw) {
      final payload = _sanitizePatientDetailsPayload(Map<String, dynamic>.from(raw));
      return {
        ...payload,
        'userId': authUid,
        'user_id': authUid,
        'profileCompleted': true,
        'updatedAt': DateTime.now().toIso8601String(),
      };
    }

    Future<void> doSet(Map<String, dynamic> body) async {
      await firestore.collection('patient_details').doc(authUid).set(body, SetOptions(merge: true));
    }

    try {
      await doSet(buildPayload(data));
      return authUid;
    } on FirebaseException catch (e) {
      debugPrint('savePatientDetails FirebaseException: ${e.code} ${e.message}');
      final retryable = e.code == 'invalid-argument' ||
          e.code == 'failed-precondition' ||
          (e.message?.toLowerCase().contains('size') ?? false) ||
          (e.message?.toLowerCase().contains('exceed') ?? false);
      if (retryable) {
        try {
          final minimal = <String, dynamic>{
            'userId': authUid,
            'user_id': authUid,
            'name': (data['name'] ?? '').toString().trim(),
            'gender': data['gender'],
            'mobile': (data['mobile'] ?? '').toString(),
            'address': (data['address'] ?? '').toString(),
            'profileImageUrl': (data['profileImageUrl'] ?? '').toString().trim(),
            'profileCompleted': true,
            'updatedAt': DateTime.now().toIso8601String(),
          };
          await doSet(_sanitizePatientDetailsPayload(minimal));
          return authUid;
        } on FirebaseException catch (e2) {
          lastPatientSaveError = _patientSaveMessageForFirebase(e2);
          debugPrint('savePatientDetails minimal retry: ${e2.code} ${e2.message}');
          return null;
        }
      }
      lastPatientSaveError = _patientSaveMessageForFirebase(e);
      return null;
    } catch (e) {
      lastPatientSaveError =
          'Could not save your profile (Firebase). Check internet and Firestore rules, then try again.';
      debugPrint('savePatientDetails: $e');
      return null;
    }
  }

  static String _patientSaveMessageForFirebase(FirebaseException e) {
    final detail = '${e.code}${e.message != null && e.message!.isNotEmpty ? ': ${e.message}' : ''}';
    switch (e.code) {
      case 'permission-denied':
        return 'Firebase permission denied ($detail). In Firebase Console → Firestore → Rules, publish rules that allow writes to patient_details/{your user id} for signed-in users (see repo firebase/firestore.rules), then run: firebase deploy --only firestore:rules';
      case 'invalid-argument':
      case 'failed-precondition':
        return e.message ??
            'Profile data was rejected ($detail). Try skipping the profile photo or use a smaller image.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Firebase is temporarily unavailable. Check your internet connection and try again.';
      default:
        return e.message ?? 'Firebase: $detail';
    }
  }

  /// Creates `patient_details/{uid}` when missing so returning patients reach the dashboard.
  static Future<bool> ensurePatientProfileIfMissing({
    required String uid,
    required String email,
    String? displayName,
  }) async {
    if (!_initialized || uid.isEmpty) return false;
    try {
      final existing = await firestore.collection('patient_details').doc(uid).get();
      if (existing.exists) return true;

      final snap = await firestore
          .collection('patient_details')
          .where('userId', isEqualTo: uid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return true;

      final name = (displayName ?? email.split('@').first).trim();
      await firestore.collection('patient_details').doc(uid).set({
        'userId': uid,
        'user_id': uid,
        'email': email.trim(),
        'name': name.isEmpty ? 'Patient' : name,
        'profileCompleted': true,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      return true;
    } catch (e, st) {
      debugPrint('ensurePatientProfileIfMissing: $e\n$st');
      return false;
    }
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>?> getPatientDetails(String userId) async {
    if (!_initialized) return null;
    try {
      // Fast path: deterministic patient profile document.
      final direct = await firestore.collection('patient_details').doc(userId).get();
      if (direct.exists) return direct;

      // Fallback for older records created with random IDs.
      final snap = await firestore
          .collection('patient_details')
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty ? snap.docs.first : null;
    } catch (e, st) {
      debugPrint('getPatientDetails: $e\n$st');
    }
    return null;
  }

  // ============ Reports ============
  static Future<String?> saveReport(Map<String, dynamic> data) async {
    if (!_initialized) return null;
    try {
      final doc = await firestore.collection('reports').add({
        ...data,
        'createdAt': data['createdAt'] ?? DateTime.now().toIso8601String(),
      });
      return doc.id;
    } catch (_) {}
    return null;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getReports(String userId) {
    return firestore
        .collection('reports')
        .where('userId', isEqualTo: userId)
        .snapshots();
  }

  // ============ Guidelines (read-only from Firestore) ============
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getGuidelinesOnce() async {
    if (!_initialized) return [];
    try {
      final snap = await firestore.collection('guidelines').get();
      return snap.docs;
    } catch (_) {}
    return [];
  }

  // ============ Storage ============
  /// Last Storage failure message (for support); cleared on successful upload.
  static String? lastStorageUploadError;

  /// Short text for SnackBars only. Log [technical] with [debugPrint] for diagnosis.
  static String humanReadableStorageFailure([String? technical]) {
    final s = (technical ?? '').toLowerCase();
    if (s.isEmpty) return 'Failed to upload photo. Please try again.';
    if (s.contains('permission-denied') || s.contains('unauthorized')) {
      return 'Permission denied. Please sign in and try again.';
    }
    if (s.contains('network') || s.contains('connection')) {
      return 'Network error. Check your connection and try again.';
    }
    if (s.contains('quota-exceeded')) {
      return 'Upload temporarily unavailable. Please try again later.';
    }
    if (s.contains('retry-limit-exceeded')) {
      return 'Upload failed after multiple retries. Please try again.';
    }
    if (s.contains('invalid-format') || s.contains('jpeg or png')) {
      return 'Please choose a JPEG or PNG photo.';
    }
    if (s.contains('file-too-large') || s.contains('5 mb')) {
      return 'File is too large. Please choose a smaller image.';
    }
    if (s.contains('canceled')) return 'Upload was cancelled.';
    if (s.contains('timeout')) return 'Upload took too long. Please try again.';
    if (s.contains('cors') || s.contains('localhost')) {
      return 'Photo upload is not available here. Try again from the mobile app.';
    }
    // object-not-found and other Firebase codes — same friendly line for users.
    return 'Failed to upload photo. Please try again.';
  }

  /// Short timeout avoids infinite spinners on Flutter Web when Storage CORS is not configured for localhost.
  static const Duration _storageUploadTimeout = Duration(seconds: 20);

  /// Upload arbitrary bytes (image, PDF, etc.) to Storage and return download URL.
  static Future<String?> uploadBytes(
    String path,
    Uint8List bytes, {
    String? contentType,
    Duration? uploadTimeout,
  }) async {
    lastStorageUploadError = null;
    if (!_initialized) return null;
    if (auth.currentUser == null) {
      lastStorageUploadError = 'permission-denied: not authenticated';
      debugPrint('Firebase Storage upload blocked: no authenticated user.');
      return null;
    }
    if (kIsWeb) {
      final host = Uri.base.host.toLowerCase();
      if (host == 'localhost' || host == '127.0.0.1') {
        lastStorageUploadError =
            'Skipped Firebase Storage upload on localhost web due to browser CORS preflight limits.';
        return null;
      }
    }
    if (bytes.isEmpty) {
      lastStorageUploadError = 'Cannot upload an empty file.';
      return null;
    }
    try {
      // Default instance follows [Firebase.initializeApp] options (same bucket as `google-services.json`).
      // Avoid `instanceFor(gs://…)` here: some setups mis-resolve `*.firebasestorage.app` and break getDownloadURL.
      final ref = _scopedStorage().ref().child(path);
      final token = _newDownloadToken();
      final meta = SettableMetadata(
        contentType: contentType,
        customMetadata: {'firebaseStorageDownloadTokens': token},
      );
      debugPrint('Firebase Storage upload start (bucket=${_bucketHostName()} path=$path bytes=${bytes.length})');
      final uploadTask = ref.putData(bytes, meta);
      await uploadTask.timeout(uploadTimeout ?? _storageUploadTimeout);
      final snap = uploadTask.snapshot;
      if (snap.state != TaskState.success) {
        lastStorageUploadError =
            'Upload did not finish successfully (state: ${snap.state}). Check Storage rules for this path.';
        debugPrint('Firebase Storage upload bad state ($path): ${snap.state}');
        return null;
      }
      try {
        return await _getDownloadUrlWithRetry(snap.ref);
      } catch (e) {
        final bucket = _bucketHostName() ?? '';
        final fallback = _manualDownloadUrl(
          bucket: bucket,
          fullPath: snap.ref.fullPath,
          token: token,
        );
        if (fallback != null) {
          debugPrint('Firebase Storage getDownloadURL fallback to token URL (path=${snap.ref.fullPath}) because: $e');
          return fallback;
        }
        rethrow;
      }
    } on FirebaseException catch (e, st) {
      final detail = 'code=${e.code} message=${e.message ?? 'n/a'}';
      lastStorageUploadError = detail;
      debugPrint('Firebase Storage upload FirebaseException ($path): $detail\n$st');
    } on TimeoutException catch (e, st) {
      lastStorageUploadError =
          'Storage upload timed out (often Web + missing Storage CORS). $e';
      debugPrint('Firebase Storage upload timed out ($path): $e\n$st');
    } catch (e, st) {
      final s = e.toString();
      if (s.contains('permission-denied') || s.contains('unauthorized')) {
        lastStorageUploadError =
            'Storage blocked this upload (permission). Deploy rules that allow your signed-in user to write this path (see firebase/storage.rules).';
      } else {
        lastStorageUploadError = s;
      }
      debugPrint('Firebase Storage upload failed ($path): $e\n$st');
    }
    return null;
  }

  static Future<String?> uploadImage(String path, Uint8List bytes) async {
    return uploadBytes(path, bytes);
  }

  // ============ User Profile ============
  static Future<void> updateUserProfile(String userId, Map<String, dynamic> data) async {
    if (!_initialized) return;
    try {
      await firestore.collection('users').doc(userId).set(data, SetOptions(merge: true));
    } catch (_) {}
  }

  // ============ Patient hair health & PDF reports (patient_details) ============

  static double hairHealthAverageScore(int strength, int scalp, int damage, int fall) {
    return (strength + scalp + (100 - damage) + (100 - fall)) / 4.0;
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> patientDetailsStream(String userId) {
    return firestore.collection('patient_details').doc(userId).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> hairScansStream(String userId) {
    return firestore.collection('patient_details').doc(userId).collection('hair_scans').snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> patientPdfReportsStream(String userId) {
    return firestore.collection('patient_details').doc(userId).collection('reports').snapshots();
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>?> getPatientReport(String userId, String reportId) async {
    if (!_initialized) return null;
    try {
      return await firestore.collection('patient_details').doc(userId).collection('reports').doc(reportId).get();
    } catch (e, st) {
      debugPrint('getPatientReport: $e\n$st');
      return null;
    }
  }

  /// Latest scalp report for a patient (for doctor clinical view).
  static Future<(String reportId, Map<String, dynamic> data)?> getLatestPatientReport(String userId) async {
    if (!_initialized || userId.trim().isEmpty) return null;
    try {
      final snap = await firestore
          .collection('patient_details')
          .doc(userId)
          .collection('reports')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      return (doc.id, doc.data());
    } catch (e, st) {
      debugPrint('getLatestPatientReport: $e\n$st');
      return null;
    }
  }

  static String? lastHairAnalysisSaveError;

  /// Persists latest metrics on [patient_details], appends [hair_scans], adds [reports] doc (batch).
  static Future<bool> saveHairAnalysisSession({
    required String userId,
    required int strength,
    required int scalp,
    required int damage,
    required int fall,
    required String reportDocId,
    required Map<String, dynamic> reportPayload,
  }) async {
    if (!_initialized) {
      lastHairAnalysisSaveError = 'Firebase is not initialized.';
      return false;
    }
    lastHairAnalysisSaveError = null;
    try {
      final slimPayload = slimReportPayloadForFirestore(reportPayload);
      final avg = hairHealthAverageScore(strength, scalp, damage, fall);
      final patientRef = firestore.collection('patient_details').doc(userId);
      final scanRef = patientRef.collection('hair_scans').doc();
      final reportRef = patientRef.collection('reports').doc(reportDocId);

      String? routineTip;
      final rec = reportPayload['recommendations'];
      if (rec is List) {
        for (final e in rec) {
          final s = e?.toString().trim();
          if (s != null && s.isNotEmpty) {
            routineTip = s.length > 200 ? '${s.substring(0, 197)}...' : s;
            break;
          }
        }
      }

      final batch = firestore.batch();
      final patientPatch = <String, dynamic>{
        'hairStrengthPct': strength,
        'hairScalpHealthPct': scalp,
        'hairDamageLevelPct': damage,
        'hairFallRiskPct': fall,
        'hairLastScanAt': FieldValue.serverTimestamp(),
      };
      if (routineTip != null) patientPatch['hairLatestRoutineTip'] = routineTip;
      batch.set(
        patientRef,
        patientPatch,
        SetOptions(merge: true),
      );
      batch.set(scanRef, {
        'createdAt': FieldValue.serverTimestamp(),
        'strength': strength,
        'scalpHealth': scalp,
        'hairDamage': damage,
        'hairFallRisk': fall,
        'averageScore': avg,
        'reportId': reportDocId,
      });
      batch.set(reportRef, {
        ...slimPayload,
        'userId': userId,
        'reportId': reportDocId,
        'createdAt': FieldValue.serverTimestamp(),
        'strength': strength,
        'scalpHealth': scalp,
        'hairDamage': damage,
        'hairFallRisk': fall,
        'averageScore': avg,
      });
      await batch.commit();
      return true;
    } on FirebaseException catch (e, st) {
      lastHairAnalysisSaveError = '${e.code}: ${e.message ?? "Firestore save failed"}';
      debugPrint('saveHairAnalysisSession: $lastHairAnalysisSaveError\n$st');
      return false;
    } catch (e, st) {
      lastHairAnalysisSaveError = e.toString();
      debugPrint('saveHairAnalysisSession: $e\n$st');
      return false;
    }
  }

  // ============ Doctor reviews (patient → doctor after appointment) ============

  static DateTime? _parseAppointmentStart(String dateIso, String timeSlot) {
    final dateStr = dateIso.trim();
    if (dateStr.isEmpty) return null;
    DateTime day;
    try {
      day = DateTime.parse(dateStr);
    } catch (_) {
      return null;
    }
    final t = timeSlot.trim();
    if (t.isEmpty) return DateTime(day.year, day.month, day.day);
    for (final pattern in ['h:mm a', 'hh:mm a', 'H:mm', 'HH:mm']) {
      try {
        final parsed = DateFormat(pattern).parse(t);
        return DateTime(day.year, day.month, day.day, parsed.hour, parsed.minute);
      } catch (_) {}
    }
    return DateTime(day.year, day.month, day.day);
  }

  static Future<bool> hasReviewForAppointment(String appointmentId) async {
    if (!_initialized || appointmentId.isEmpty) return false;
    try {
      final snap = await firestore
          .collection('doctor_reviews')
          .where('appointmentId', isEqualTo: appointmentId)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasPatientReviewedDoctor({
    required String patientUserId,
    required String doctorId,
  }) async {
    if (!_initialized || patientUserId.isEmpty || doctorId.isEmpty) return false;
    try {
      final snap = await firestore
          .collection('doctor_reviews')
          .where('userId', isEqualTo: patientUserId)
          .where('doctorId', isEqualTo: doctorId)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasReviewPromptShownForDoctor({
    required String patientUserId,
    required String doctorId,
  }) async {
    if (!_initialized || patientUserId.isEmpty || doctorId.isEmpty) return false;
    try {
      final snap = await firestore.collection('patient_details').doc(patientUserId).get();
      final data = snap.data();
      final shown = data?['reviewPromptShownDoctorIds'];
      if (shown is! List) return false;
      return shown.map((e) => e.toString()).contains(doctorId);
    } catch (_) {
      return false;
    }
  }

  /// First past appointment without a review (for post-visit prompt).
  static Future<PendingDoctorReview?> getNextPendingDoctorReview(String patientUserId) async {
    if (!_initialized || patientUserId.isEmpty) return null;
    try {
      final snap = await firestore
          .collection('appointments')
          .where('userId', isEqualTo: patientUserId)
          .limit(80)
          .get();
      final now = DateTime.now();
      final pending = <({DateTime end, String docId, Map<String, dynamic> data})>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final status = (d['status'] ?? '').toString().toLowerCase();
        if (status == 'cancelled' || status == 'declined') continue;
        final start = _parseAppointmentStart(
          (d['date'] ?? '').toString(),
          (d['timeSlot'] ?? d['time'] ?? '').toString(),
        );
        if (start == null) continue;
        final end = start.add(const Duration(minutes: 45));
        if (!now.isAfter(end)) continue;
        pending.add((end: end, docId: doc.id, data: d));
      }
      pending.sort((a, b) => b.end.compareTo(a.end));
      for (final row in pending) {
        final prompted = row.data['reviewPromptShown'] == true;
        if (prompted) continue;
        if (await hasReviewForAppointment(row.docId)) continue;
        final doctorId = (row.data['doctorId'] ?? row.data['doctorID'] ?? '').toString();
        if (doctorId.isEmpty) continue;
        final reviewedDoctor = await hasPatientReviewedDoctor(
          patientUserId: patientUserId,
          doctorId: doctorId,
        );
        if (reviewedDoctor) continue;
        final promptedDoctor = await hasReviewPromptShownForDoctor(
          patientUserId: patientUserId,
          doctorId: doctorId,
        );
        if (promptedDoctor) continue;
        return PendingDoctorReview(
          appointmentId: row.docId,
          doctorId: doctorId,
          patientUserId: patientUserId,
          doctorName: (row.data['doctorName'] ?? row.data['doctor_name'] ?? 'Doctor').toString(),
          dateLabel: (row.data['date'] ?? '').toString(),
          timeSlot: (row.data['timeSlot'] ?? row.data['time'] ?? '').toString(),
        );
      }
    } catch (e, st) {
      debugPrint('getNextPendingDoctorReview: $e\n$st');
    }
    return null;
  }

  /// Marks that review prompt has already been shown for this appointment.
  static Future<void> markReviewPromptShown(String appointmentId) async {
    if (!_initialized || appointmentId.trim().isEmpty) return;
    try {
      await firestore.collection('appointments').doc(appointmentId).set({
        'reviewPromptShown': true,
      }, SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('markReviewPromptShown: $e\n$st');
    }
  }

  /// Marks one-time review prompt already shown for this doctor (per patient).
  static Future<void> markReviewPromptShownForDoctor({
    required String patientUserId,
    required String doctorId,
  }) async {
    if (!_initialized || patientUserId.trim().isEmpty || doctorId.trim().isEmpty) return;
    try {
      await firestore.collection('patient_details').doc(patientUserId).set({
        'reviewPromptShownDoctorIds': FieldValue.arrayUnion([doctorId]),
      }, SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('markReviewPromptShownForDoctor: $e\n$st');
    }
  }

  static Future<bool> submitDoctorReview({
    required String appointmentId,
    required String doctorId,
    required String patientUserId,
    required int stars,
    required String comment,
    String? doctorName,
  }) async {
    if (!_initialized) return false;
    if (appointmentId.isEmpty || doctorId.isEmpty || patientUserId.isEmpty) return false;
    if (stars < 1 || stars > 5) return false;
    try {
      if (await hasReviewForAppointment(appointmentId)) return true;
      await firestore.collection('doctor_reviews').add({
        'appointmentId': appointmentId,
        'doctorId': doctorId,
        'userId': patientUserId,
        'stars': stars,
        'comment': comment.trim(),
        'doctorName': doctorName?.trim() ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e, st) {
      debugPrint('submitDoctorReview: $e\n$st');
      return false;
    }
  }

  static Future<Map<String, DoctorRatingSummary>> getDoctorRatingSummaries(Iterable<String> doctorIds) async {
    final ids = doctorIds.where((e) => e.trim().isNotEmpty).toSet();
    if (ids.isEmpty || !_initialized) return {};
    final byDoctor = <String, List<int>>{};
    try {
      final snap = await firestore.collection('doctor_reviews').limit(500).get();
      for (final doc in snap.docs) {
        final d = doc.data();
        final did = (d['doctorId'] ?? '').toString();
        if (!ids.contains(did)) continue;
        final stars = (d['stars'] as num?)?.toInt() ?? int.tryParse('${d['stars']}') ?? 0;
        if (stars < 1 || stars > 5) continue;
        byDoctor.putIfAbsent(did, () => []).add(stars);
      }
    } catch (e, st) {
      debugPrint('getDoctorRatingSummaries: $e\n$st');
    }
    final out = <String, DoctorRatingSummary>{};
    for (final id in ids) {
      final list = byDoctor[id];
      if (list == null || list.isEmpty) {
        out[id] = const DoctorRatingSummary(average: 0, count: 0);
      } else {
        final sum = list.fold<int>(0, (a, b) => a + b);
        out[id] = DoctorRatingSummary(average: sum / list.length, count: list.length);
      }
    }
    return out;
  }

  // ============ Chat (patient ↔ doctor, real-time) ============

  static const String chatSystemSenderId = '__system__';

  static DateTime? _chatTimestamp(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> chatConversationsForPatientStream(String patientId) {
    return firestore.collection('chat_conversations').where('patientId', isEqualTo: patientId).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> chatConversationsForDoctorStream(String doctorId) {
    return firestore.collection('chat_conversations').where('doctorId', isEqualTo: doctorId).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> chatMessagesStream(String conversationId) {
    return firestore
        .collection('chat_conversations')
        .doc(conversationId)
        .collection('messages')
        .snapshots();
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getChatMessagesOnce(
    String conversationId,
  ) async {
    if (!_initialized || conversationId.isEmpty) return [];
    try {
      final snap = await firestore
          .collection('chat_conversations')
          .doc(conversationId)
          .collection('messages')
          .get();
      final docs = snap.docs.toList();
      docs.sort((a, b) {
        final ta = _chatTimestamp(a.data()['timestamp']);
        final tb = _chatTimestamp(b.data()['timestamp']);
        if (ta != null && tb != null) return ta.compareTo(tb);
        return a.id.compareTo(b.id);
      });
      return docs;
    } catch (e, st) {
      debugPrint('getChatMessagesOnce: $e\n$st');
      return [];
    }
  }

  /// Creates conversation + optional system message when doctor confirms appointment.
  static String? lastChatSendError;

  /// User-facing hint when Firestore rejects chat writes (rules not deployed, wrong account, etc.).
  static String friendlyFirestoreError(Object error) {
    final s = error.toString().toLowerCase();
    if (s.contains('permission-denied') || s.contains('permission_denied')) {
      return 'Firestore blocked this action. From the project root run: '
          'py backend\\scripts\\deploy_firestore_rules.py '
          '(or paste firebase/firestore.rules in Firebase Console → Firestore → Rules → Publish).';
    }
    if (s.contains('unauthenticated')) {
      return 'You are not signed in. Sign out and sign in again, then retry.';
    }
    if (s.contains('not-found')) {
      return 'Chat thread not found in the database.';
    }
    return error.toString();
  }

  static bool _appointmentAcceptedFromData(Map<String, dynamic> data) {
    if (!data.containsKey('appointmentAccepted')) return true;
    final v = data['appointmentAccepted'];
    if (v == true) return true;
    if (v is String && v.toLowerCase() == 'true') return true;
    return false;
  }

  static Future<bool> ensureChatConversation({
    required String conversationId,
    required String appointmentId,
    required String patientId,
    required String doctorId,
    required String patientName,
    required String doctorName,
    required String systemMessageText,
  }) async {
    if (!_initialized) return false;
    lastChatSendError = null;
    try {
      final ref = firestore.collection('chat_conversations').doc(conversationId);
      final existing = await ref.get();
      final now = FieldValue.serverTimestamp();
      if (!existing.exists) {
        await ref.set({
          'conversationId': conversationId,
          'appointmentId': appointmentId,
          'patientId': patientId,
          'doctorId': doctorId,
          'patientName': patientName,
          'doctorName': doctorName,
          'lastMessage': systemMessageText,
          'lastMessageTime': now,
          'appointmentAccepted': true,
          'unreadCountPatient': 0,
          'unreadCountDoctor': 0,
          'createdAt': now,
        });
      } else {
        await ref.set({
          'appointmentAccepted': true,
          'appointmentId': appointmentId,
          'patientId': patientId,
          'doctorId': doctorId,
          'patientName': patientName,
          'doctorName': doctorName,
          'lastMessage': systemMessageText,
          'lastMessageTime': now,
        }, SetOptions(merge: true));
      }

      try {
        final msgs = await ref.collection('messages').limit(1).get();
        if (msgs.docs.isEmpty) {
          await ref.collection('messages').add({
            'conversationId': conversationId,
            'senderId': chatSystemSenderId,
            'text': systemMessageText,
            'timestamp': now,
            'isRead': false,
          });
        }
      } catch (e, st) {
        debugPrint('ensureChatConversation system message (non-fatal): $e\n$st');
      }
      return true;
    } catch (e, st) {
      lastChatSendError = friendlyFirestoreError(e);
      debugPrint('ensureChatConversation: $e\n$st');
      return false;
    }
  }

  static Future<bool> sendChatMessage({
    required String conversationId,
    required String senderId,
    required String text,
    required String patientId,
    required String doctorId,
    String? systemMessageFallback,
    String? appointmentId,
    String? patientDisplayName,
    String? doctorDisplayName,
  }) async {
    if (!_initialized || text.trim().isEmpty) return false;
    lastChatSendError = null;
    try {
      final ref = firestore.collection('chat_conversations').doc(conversationId);
      var conv = await ref.get();
      if (!conv.exists) {
        final apptId = (appointmentId ?? '').trim();
        if (apptId.isEmpty) {
          lastChatSendError = 'Chat thread not saved to cloud yet.';
          return false;
        }
        final ok = await ensureChatConversation(
          conversationId: conversationId,
          appointmentId: apptId,
          patientId: patientId,
          doctorId: doctorId,
          patientName: patientDisplayName ?? 'Patient',
          doctorName: doctorDisplayName ?? 'Doctor',
          systemMessageText: systemMessageFallback ?? 'Appointment confirmed. You can now message each other.',
        );
        if (!ok) {
          lastChatSendError = 'Chat thread is not in Firestore yet.';
          return false;
        }
        conv = await ref.get();
      }
      if (!conv.exists) {
        lastChatSendError = 'Chat thread not found.';
        return false;
      }
      final data = conv.data()!;
      if (!_appointmentAcceptedFromData(data)) {
        lastChatSendError = 'Appointment is not confirmed yet.';
        return false;
      }

      final docPatient = (data['patientId'] ?? patientId).toString();
      final docDoctor = (data['doctorId'] ?? doctorId).toString();
      if (senderId != docPatient && senderId != docDoctor) {
        lastChatSendError = 'You are not a participant in this chat thread.';
        return false;
      }

      final isPatient = senderId == docPatient;
      final now = FieldValue.serverTimestamp();
      await ref.collection('messages').add({
        'conversationId': conversationId,
        'senderId': senderId,
        'text': text.trim(),
        'timestamp': now,
        'isRead': false,
      });

      try {
        final unreadPatient = (data['unreadCountPatient'] as num?)?.toInt() ?? 0;
        final unreadDoctor = (data['unreadCountDoctor'] as num?)?.toInt() ?? 0;
        await ref.update({
          'lastMessage': text.trim(),
          'lastMessageTime': now,
          'unreadCountPatient': isPatient ? unreadPatient : unreadPatient + 1,
          'unreadCountDoctor': isPatient ? unreadDoctor + 1 : unreadDoctor,
        });
      } catch (e) {
        debugPrint('sendChatMessage: conversation metadata update failed: $e');
      }
      return true;
    } catch (e, st) {
      lastChatSendError = friendlyFirestoreError(e);
      debugPrint('sendChatMessage: $e\n$st');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getChatConversationData(String conversationId) async {
    if (!_initialized || conversationId.isEmpty) return null;
    try {
      final doc = await firestore.collection('chat_conversations').doc(conversationId).get();
      return doc.data();
    } catch (e, st) {
      debugPrint('getChatConversationData: $e\n$st');
      return null;
    }
  }

  static Future<void> markChatConversationRead({
    required String conversationId,
    required String role,
  }) async {
    if (!_initialized) return;
    try {
      final ref = firestore.collection('chat_conversations').doc(conversationId);
      if (role == 'patient') {
        await ref.update({'unreadCountPatient': 0});
      } else if (role == 'doctor') {
        await ref.update({'unreadCountDoctor': 0});
      }
    } catch (e, st) {
      debugPrint('markChatConversationRead: $e\n$st');
    }
  }

  static DateTime? chatTimestampFromField(dynamic v) => _chatTimestamp(v);
}

/// Completed appointment eligible for a patient review prompt.
class PendingDoctorReview {
  const PendingDoctorReview({
    required this.appointmentId,
    required this.doctorId,
    required this.patientUserId,
    required this.doctorName,
    required this.dateLabel,
    required this.timeSlot,
  });

  final String appointmentId;
  final String doctorId;
  final String patientUserId;
  final String doctorName;
  final String dateLabel;
  final String timeSlot;
}

class DoctorRatingSummary {
  const DoctorRatingSummary({required this.average, required this.count});

  final double average;
  final int count;

  bool get hasReviews => count > 0;
}
