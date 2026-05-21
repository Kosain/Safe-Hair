import 'package:flutter/material.dart';

import '../services/firebase_service.dart';

/// Shown when [FirebaseService.isInitialized] is false so users see why login/sign-up cannot work.
class FirebaseInitBanner extends StatelessWidget {
  const FirebaseInitBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (FirebaseService.isInitialized) return const SizedBox.shrink();
    final msg = FirebaseService.lastInitError ??
        'Firebase did not start on this build. Check internet, reinstall the app, and verify firebase_options / google-services.json match your Firebase project.';
    return Material(
      color: Colors.orange.shade50,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: Colors.orange.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
