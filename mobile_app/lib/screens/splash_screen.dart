import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/intro_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateNext();
  }

  Future<void> _navigateNext() async {
    final seenIntroFuture = IntroPreferences.hasSeenIntro();
    await Future.delayed(const Duration(seconds: 2));
    final seenIntro = await seenIntroFuture;
    if (!mounted) return;
    context.go(seenIntro ? '/role' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD8E5D5),
      body: Align(
        alignment: const Alignment(0, -0.02),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Image(
               image: AssetImage('assets/logo.png'),
                width: 56,
                height: 56,
                fit: BoxFit.contain,
              ),
            SizedBox(height: 10),
            Text(
              'SAFE HAIR',
              style: TextStyle(
                color: Color(0xFF2F2F2F),
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
