import 'package:flutter/foundation.dart';
import '../services/firebase_service.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  String? _userId;
  String? _userEmail;
  String? _userName;
  String? _userPhotoUrl;
  Uint8List? _userPhotoBytes;
  String _role = 'patient';
  bool _profileChecked = false;
  bool _isDoctorRegistered = false;
  bool _isPatientRegistered = false;

  /// After a completed registration fetch, used to avoid forcing `/gate` on token / profile updates for the same uid.
  String? _lastRegistrationCheckUid;
  String? _lastAuthError;

  String _normalizeRole(String? value) {
    final raw = (value ?? '').trim().toLowerCase();
    if (raw == 'doctor' || raw == 'clinic') return 'doctor';
    if (raw == 'patient' || raw == 'user') return 'patient';
    return _role;
  }

  bool get profileChecked => _profileChecked;
  bool get isDoctorRegistered => _isDoctorRegistered;
  bool get isPatientRegistered => _isPatientRegistered;

  String? get userId => _userId;
  String? get userEmail => _userEmail;
  String? get userName => _userName ?? _userEmail?.split('@').first;
  String? get userPhotoUrl => _userPhotoUrl;
  Uint8List? get userPhotoBytes => _userPhotoBytes;
  String get role => _role;
  bool get isAuthenticated => userId != null;
  String? get lastAuthError => _lastAuthError;

  AuthProvider() {
    if (!FirebaseService.isInitialized) {
      _profileChecked = true;
      _isDoctorRegistered = true;
      _isPatientRegistered = true;
      return;
    }

    final user = FirebaseService.currentUser;
    if (user != null) {
      _userId = user.uid;
      _userEmail = user.email;
      _userName = user.displayName ?? user.email?.split('@').first;
      _userPhotoUrl = user.photoURL;
      ApiService().attachUserContext(userId: user.uid, email: user.email ?? '');
    }

    // Keep auth state + registration status in sync.
    FirebaseService.authStateChanges.listen((user) async {
      if (user != null) {
        _userId = user.uid;
        _userEmail = user.email;
        _userName = user.displayName ?? user.email?.split('@').first;
        _userPhotoUrl = user.photoURL;
        ApiService().attachUserContext(
          userId: user.uid,
          email: user.email ?? '',
        );
      } else {
        _userId = null;
        _userEmail = null;
        _userName = null;
        _userPhotoUrl = null;
        _userPhotoBytes = null;
        _lastRegistrationCheckUid = null;
        ApiService().clearSession();
      }
      await _refreshRegistrationFlags();
    });

    // Initial check (for app refresh scenarios).
    _refreshRegistrationFlags();
  }

  void setRole(String role) {
    _role = role;
    notifyListeners();
  }

  Future<void> _refreshRegistrationFlags() async {
    final uid = _userId;
    final uidChanged = uid != _lastRegistrationCheckUid;
    if (uidChanged) {
      _profileChecked = false;
      notifyListeners();
    }

    if (uid == null) {
      _lastRegistrationCheckUid = null;
      _isDoctorRegistered = false;
      _isPatientRegistered = false;
      _profileChecked = true;
      notifyListeners();
      return;
    }

    if (!FirebaseService.isInitialized) {
      // Firebase not configured -> do not block app flow.
      _isDoctorRegistered = true;
      _isPatientRegistered = true;
      _lastRegistrationCheckUid = uid;
      _profileChecked = true;
      notifyListeners();
      return;
    }

    try {
      final doctorProfile = await FirebaseService.getDoctorProfile(
        uid,
      ).timeout(const Duration(seconds: 6), onTimeout: () => null);
      final patientSnap = await FirebaseService.getPatientDetails(
        uid,
      ).timeout(const Duration(seconds: 6), onTimeout: () => null);

      _isDoctorRegistered =
          doctorProfile != null && (doctorProfile['profileCompleted'] == true);
      _isPatientRegistered = patientSnap != null;
    } catch (_) {
      // Never keep the app stuck on /gate if profile checks fail.
      // Fail-open based on selected role so user can proceed.
      if (_role == 'doctor') {
        _isDoctorRegistered = true;
      } else {
        _isPatientRegistered = true;
      }
    }

    // If they are registered as one role, auto-select it.
    if (_isDoctorRegistered) {
      _role = 'doctor';
    } else if (_isPatientRegistered) {
      _role = 'patient';
    }

    _lastRegistrationCheckUid = uid;
    _profileChecked = true;
    notifyListeners();
  }

  /// Public trigger for screens to re-check registration after profile updates.
  Future<void> refreshRegistrationStatus() => _refreshRegistrationFlags();

  /// After a successful doctor profile write, use if Firestore read is briefly stale.
  void markDoctorRegistered() {
    final u = _userId;
    if (u != null) _lastRegistrationCheckUid = u;
    _isDoctorRegistered = true;
    _profileChecked = true;
    _role = 'doctor';
    notifyListeners();
  }

  void markPatientRegistered() {
    final u = _userId;
    if (u != null) _lastRegistrationCheckUid = u;
    _isPatientRegistered = true;
    _profileChecked = true;
    _role = 'patient';
    notifyListeners();
  }

  Future<bool> signInWithEmail(String email, String password) async {
    _lastAuthError = null;
    final cred = await FirebaseService.signInWithEmail(email, password);
    if (cred != null && cred.user != null) {
      _userId = cred.user!.uid;
      _userEmail = cred.user!.email ?? email;
      _userName = cred.user!.displayName ?? email.split('@').first;
      ApiService().attachUserContext(
        userId: cred.user!.uid,
        email: cred.user!.email ?? email,
      );
      notifyListeners();
      return true;
    }
    _lastAuthError = FirebaseService.lastAuthError ?? 'Invalid email or password.';
    return false;
  }

  Future<bool> signUpWithEmail(
    String email,
    String password, {
    String? name,
  }) async {
    _lastAuthError = null;
    final cred = await FirebaseService.signUpWithEmail(email, password);
    if (cred != null && cred.user != null) {
      if (name != null && name.isNotEmpty) {
        await cred.user!.updateDisplayName(name);
      }
      _userId = cred.user!.uid;
      _userEmail = cred.user!.email ?? email;
      _userName = cred.user!.displayName ?? name ?? email.split('@').first;
      ApiService().attachUserContext(
        userId: cred.user!.uid,
        email: cred.user!.email ?? email,
      );
      notifyListeners();
      return true;
    }
    _lastAuthError = FirebaseService.lastAuthError ?? 'Could not create account. Please try again.';
    return false;
  }

  Future<bool> signInWithGoogle() async {
    if (FirebaseService.isInitialized) {
      final cred = await FirebaseService.signInWithGoogle();
      if (cred != null && cred.user != null) {
        _userId = cred.user!.uid;
        _userEmail = cred.user!.email;
        _userName =
            cred.user!.displayName ?? cred.user!.email?.split('@').first;
        ApiService().attachUserContext(
          userId: cred.user!.uid,
          email: cred.user!.email ?? '',
        );
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  Future<bool> signInWithFacebook() async {
    if (FirebaseService.isInitialized) {
      final cred = await FirebaseService.signInWithFacebook();
      if (cred != null && cred.user != null) {
        _userId = cred.user!.uid;
        _userEmail = cred.user!.email;
        _userName =
            cred.user!.displayName ?? cred.user!.email?.split('@').first;
        ApiService().attachUserContext(
          userId: cred.user!.uid,
          email: cred.user!.email ?? '',
        );
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  Future<void> signOut() async {
    if (FirebaseService.isInitialized) await FirebaseService.signOut();
    ApiService().clearSession();
    _lastRegistrationCheckUid = null;
    _userId = null;
    _userEmail = null;
    _userName = null;
    _userPhotoUrl = null;
    _userPhotoBytes = null;
    _isDoctorRegistered = false;
    _isPatientRegistered = false;
    _profileChecked = true;
    notifyListeners();
  }

  void setUserProfile(String name) {
    _userName = name;
    notifyListeners();
  }

  void setUserPhoto({String? url, Uint8List? bytes}) {
    if (url != null) _userPhotoUrl = url;
    if (bytes != null) _userPhotoBytes = bytes;
    notifyListeners();
  }
}
