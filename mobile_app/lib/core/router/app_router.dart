import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/signup_page.dart';
import '../../features/booking/presentation/booking_page.dart';
import '../../features/consultants/presentation/consultants_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/onboarding/presentation/onboarding_page.dart';
import '../../features/reports/presentation/reports_page.dart';
import '../../features/scan/presentation/scan_page.dart';

GoRouter buildAppRouter() {
  return GoRouter(
    initialLocation: '/auth/login',
    routes: [
      GoRoute(path: '/auth/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/auth/signup', builder: (_, __) => const SignupPage()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingPage()),
      GoRoute(path: '/dashboard', builder: (_, __) => const DashboardPage()),
      GoRoute(path: '/scan', builder: (_, __) => const ScanPage()),
      GoRoute(path: '/reports', builder: (_, __) => const ReportsPage()),
      GoRoute(path: '/consultants', builder: (_, __) => const ConsultantsPage()),
      GoRoute(path: '/booking', builder: (_, __) => const BookingPage()),
    ],
  );
}
