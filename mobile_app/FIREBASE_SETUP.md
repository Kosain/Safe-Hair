# Firebase Setup Guide for Safe Hair

To enable Firebase data persistence (appointments, patient details), follow these steps:

## 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create a new project or use existing
3. Enable **Authentication** (Email/Password, Google, Facebook)
4. Enable **Cloud Firestore** - Create database in production/test mode
5. Enable **Storage** - for scalp/graft images

## 2. Flutter Configuration

```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Configure Firebase for your project
flutterfire configure
```

This generates:
- `lib/firebase_options.dart` - Platform-specific config
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

## 3. Update main.dart

```dart
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FirebaseService.init();
  runApp(const SafeHairApp());
}
```

## 4. Web Setup

Add to `web/index.html` before `</body>`:

```html
<script src="https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.7.0/firebase-firestore-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.7.0/firebase-auth-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.7.0/firebase-storage-compat.js"></script>
<script>
  const firebaseConfig = {
    apiKey: "YOUR_API_KEY",
    authDomain: "YOUR_PROJECT.firebaseapp.com",
    projectId: "YOUR_PROJECT_ID",
    storageBucket: "YOUR_PROJECT.appspot.com",
    messagingSenderId: "YOUR_SENDER_ID",
    appId: "YOUR_APP_ID"
  };
  firebase.initializeApp(firebaseConfig);
</script>
```

## 5. Firestore Security Rules (Example)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /appointments/{docId} {
      allow read, write: if request.auth != null;
    }
    match /patient_details/{docId} {
      allow read, write: if request.auth != null;
    }
  }
}
```

## 6. Replace Mock Auth

Update `AuthProvider` to use Firebase Auth:

```dart
import 'package:firebase_auth/firebase_auth.dart';

Future<void> signInWithEmail(String email, String password) async {
  final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
    email: email,
    password: password,
  );
  _userId = cred.user?.uid;
  _userEmail = cred.user?.email;
  // ...
}
```
