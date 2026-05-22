// Firebase options for Safe Hair — project safe-hair-274
// Keep in sync with: firebase/project.json and backend/safe_hair_project.py

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD1VUk348SOnvBkD0SEmWge_f6urQBBFuU',
    appId: '1:484504357959:android:9b4d365c7b9df459163562',
    messagingSenderId: '484504357959',
    projectId: 'safe-hair-274',
    // Must match `android/app/google-services.json` project_info.storage_bucket
    // (default bucket is often *.firebasestorage.app; *.appspot.com alone breaks uploads).
    storageBucket: 'safe-hair-274.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD1VUk348SOnvBkD0SEmWge_f6urQBBFuU',
    appId: '1:484504357959:ios:placeholder',
    messagingSenderId: '484504357959',
    projectId: 'safe-hair-274',
    storageBucket: 'safe-hair-274.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD1VUk348SOnvBkD0SEmWge_f6urQBBFuU',
    appId: '1:484504357959:web:288771c4f683c3cb163562',
    messagingSenderId: '484504357959',
    projectId: 'safe-hair-274',
    authDomain: 'safe-hair-274.firebaseapp.com',
    storageBucket: 'safe-hair-274.firebasestorage.app',
    measurementId: 'G-6M5YDRKJKF',
  );

}