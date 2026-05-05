import 'package:firebase_auth/firebase_auth.dart';

import '../core/dio_client.dart';
import '../core/constants/app_constants.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> notifyBackendSession({
    required String userId,
    required String email,
  }) async {
    await DioClient.instance.post(
      '${AppConstantsV2.apiV1}/auth/session',
      data: {'user_id': userId, 'email': email},
    );
  }
}
