import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';

class FirebaseService {
  static bool _initialized = false;
  static String? lastAuthError;
  static String? lastInitError;

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
        webExperimentalForceLongPolling: true,
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

  static Future<UserCredential?> signInWithEmail(String email, String password) async {
    lastAuthError = null;
    if (!_initialized) {
      lastAuthError = lastInitError ?? 'Firebase is not initialized on this app build.';
      return null;
    }
    try {
      return await auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase signInWithEmail error: code=${e.code} message=${e.message}');
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        lastAuthError = 'Invalid email or password.';
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
    if (!_initialized) return null;
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
    }
    return null;
  }

  static Future<UserCredential?> signInWithFacebook() async {
    if (!_initialized) return null;
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
    }
    return null;
  }

  // ============ Doctors (separate collection) ============
  /// Cleared on each successful save; explains last failure for UI.
  static String? lastDoctorProfileSaveError;

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
      return doc.data();
    } catch (_) {}
    return null;
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

  static Future<List<Map<String, dynamic>>> getVerifiedDoctorsOnce() async {
    if (!_initialized) return [];
    try {
      final snap = await firestore.collection('doctors').where('profileCompleted', isEqualTo: true).get();
      final rows = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      rows.sort((a, b) {
        final ac = ((a['activeDoctorsCount'] ?? 0) is num)
            ? (a['activeDoctorsCount'] as num).toInt()
            : int.tryParse('${a['activeDoctorsCount'] ?? 0}') ?? 0;
        final bc = ((b['activeDoctorsCount'] ?? 0) is num)
            ? (b['activeDoctorsCount'] as num).toInt()
            : int.tryParse('${b['activeDoctorsCount'] ?? 0}') ?? 0;
        return bc.compareTo(ac);
      });
      return rows;
    } catch (_) {}
    return [];
  }

  static Future<bool> isAppointmentSlotBooked({
    required String doctorId,
    required String date,
    required String timeSlot,
  }) async {
    if (!_initialized) return false;
    try {
      final snap = await firestore
          .collection('appointments')
          .where('doctorId', isEqualTo: doctorId)
          .where('date', isEqualTo: date)
          .where('timeSlot', isEqualTo: timeSlot)
          .limit(1)
          .get();
      // If it exists, treat as booked to prevent double-booking.
      if (snap.docs.isEmpty) return false;
      final data = snap.docs.first.data();
      final s = (data['status'] ?? 'confirmed').toString().toLowerCase();
      // Finished or rejected bookings free the slot for a new reservation.
      if (s == 'cancelled' || s == 'declined' || s == 'completed') return false;
      return s == 'confirmed' || s == 'pending' || s.isEmpty;
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
      final snap = await firestore
          .collection('appointments')
          .where('doctorId', isEqualTo: doctorId)
          .get();
      final booked = <String>{};
      for (final doc in snap.docs) {
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

  static Stream<QuerySnapshot<Map<String, dynamic>>> getAppointmentsForDoctor(String doctorId) {
    return firestore
        .collection('appointments')
        .where('doctorId', isEqualTo: doctorId)
        .snapshots();
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
      final doc = await firestore.collection('appointments').add(data);
      return doc.id;
    } catch (_) {}
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
      // Always use the signed-in user's uid as document id (must match Firestore rules).
      await firestore.collection('patient_details').doc(authUid).set(
        {
          ...data,
          'userId': authUid,
          'user_id': authUid,
          'profileCompleted': true,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        SetOptions(merge: true),
      );
      return authUid;
    } on FirebaseException catch (e) {
      lastPatientSaveError = _patientSaveMessageForFirebase(e);
      debugPrint('savePatientDetails FirebaseException: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      lastPatientSaveError =
          'Could not save your profile (Firebase). Check internet and Firestore rules, then try again.';
      debugPrint('savePatientDetails: $e');
      return null;
    }
  }

  static String _patientSaveMessageForFirebase(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Could not save your profile (Firebase). Check internet and Firestore rules, then try again.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Firebase is temporarily unavailable. Check your internet connection and try again.';
      default:
        return e.message ??
            'Could not save your profile (Firebase). Check internet and Firestore rules, then try again.';
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
    } catch (_) {}
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
    if (!_initialized) return false;
    try {
      final avg = hairHealthAverageScore(strength, scalp, damage, fall);
      final patientRef = firestore.collection('patient_details').doc(userId);
      final scanRef = patientRef.collection('hair_scans').doc();
      final reportRef = patientRef.collection('reports').doc(reportDocId);

      final batch = firestore.batch();
      batch.set(
        patientRef,
        {
          'hairStrengthPct': strength,
          'hairScalpHealthPct': scalp,
          'hairDamageLevelPct': damage,
          'hairFallRiskPct': fall,
          'hairLastScanAt': FieldValue.serverTimestamp(),
        },
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
        ...reportPayload,
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
    } catch (e, st) {
      debugPrint('saveHairAnalysisSession: $e\n$st');
      return false;
    }
  }
}
