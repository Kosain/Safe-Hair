import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_colors.dart';
import '../services/intro_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _pages = [
    {
      'title': 'Find Trusted Doctors',
      'desc':
          'Connect with verified hair and scalp specialists who understand your unique needs and history.',
      'asset': 'assets/Intro_1.png',
    },
    {
      'title': 'Easy Appointments',
      'desc':
          'Book, reschedule, and track consultations in a few taps with reminders tailored to your routine.',
      'asset': 'assets/Intro_2.png',
    },
    {
      'title': 'Choose Best Doctors',
      'desc':
          'Review experience, location, and availability to select the right doctor for your hair journey.',
      'asset': 'assets/Intro_3.jpg',
    },
  ];

  @override
  void initState() {
    super.initState();
    _redirectIfAlreadySeen();
  }

  Future<void> _redirectIfAlreadySeen() async {
    if (await IntroPreferences.hasSeenIntro()) {
      if (!mounted) return;
      context.go('/role');
    }
  }

  Future<void> _finishIntro() async {
    await IntroPreferences.markIntroSeen();
    if (!mounted) return;
    context.go('/role');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final heroSize = height < 760 ? 190.0 : 230.0;
    final topGap = height < 760 ? 12.0 : 24.0;
    final sectionGap = height < 760 ? 18.0 : 32.0;
    return Scaffold(
      backgroundColor: AppColors.primaryGreen,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(height: topGap),
            Column(
              children: [
                const Image(
                  image: AssetImage('assets/logo.png'),
                  width: 56,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 8),
                Text(
                  'SAFE HAIR',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            SizedBox(height: sectionGap),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) {
                  final page = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: constraints.maxHeight),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: heroSize,
                                  height: heroSize,
                                  child: ClipOval(
                                    child: Image.asset(
                                      page['asset']!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Icon(
                                        i == 0
                                            ? Icons.medical_services
                                            : (i == 1 ? Icons.calendar_today : Icons.science),
                                        size: 80,
                                        color: Colors.teal.shade300,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: sectionGap),
                                Text(
                                  page['title']!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  page['desc']!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textGrey,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == i ? AppColors.darkButton : AppColors.textGrey.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (_currentPage > 0) {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else {
                          _finishIntro();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: Text(_currentPage == 0 ? 'Skip' : 'Back'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (_currentPage < 2) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else {
                          _finishIntro();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: Text(_currentPage < 2 ? 'Next' : 'Get Started'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}