import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import '../screens/splash_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/role_selection_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_patient_screen.dart';
import '../screens/auth/signup_doctor_screen.dart';
import '../screens/patient_details_screen.dart';
import '../screens/appointment_screen.dart';
import '../screens/doctor_list_screen.dart';
import '../screens/patient_my_scans_screen.dart';
import '../screens/patient_my_appointments_screen.dart';
import '../screens/patient_my_report_screen.dart';
import '../screens/patient_appointment_booking_screen.dart';
import '../screens/patient_appointment_success_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/clinic_details_screen.dart';
import '../screens/patient_profile_edit_screen.dart';
import '../screens/scalp_report_detail_screen.dart';
import '../screens/mobile/mobile_dashboard_screen.dart';
import '../screens/scalp_analyzer_screen.dart';
import '../screens/graft_result_screen.dart';
import '../screens/recommendations_screen.dart';
import '../screens/guidelines_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/doctor_dashboard_redesign_screen.dart';
import '../screens/doctor_profile_edit_screen.dart';
import '../screens/doctor_registration/doctor_profile_registration_screen.dart';
import '../screens/web/doctor_dashboard_web.dart';
import '../screens/web/patient_dashboard_web.dart';
import '../screens/web/patient_my_appointments_web.dart';
import '../screens/web/patient_my_report_web.dart';
import '../screens/web/patient_my_scans_web.dart';
import '../screens/gate_screen.dart';
import '../models/scalp_analysis_model.dart';
import '../providers/auth_provider.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createRouter(AuthProvider authProvider) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: kIsWeb ? '/role' : '/',
    refreshListenable: authProvider,
    redirect: (context, state) {
      final isLoggedIn = authProvider.isAuthenticated;
      final path = state.matchedLocation;
      final isAuthRoute =
          path.startsWith('/login') || path.startsWith('/signup');
      final isOnboarding = path == '/' || path.startsWith('/onboarding');

      // Web: bare host URL is usually "/" (not "#/role") — avoid Splash → Onboarding trap; go to role/login entry.
      if (kIsWeb && path == '/') {
        if (!isLoggedIn) return '/role';
        if (!authProvider.profileChecked) return '/gate';
        if (authProvider.role == 'doctor') {
          return authProvider.isDoctorRegistered ? '/doctor-dashboard' : '/doctor-onboarding';
        }
        return authProvider.isPatientRegistered ? '/dashboard' : '/patient-details';
      }

      // Public onboarding screens
      if (isOnboarding) return null;

      // Allow gate screen to render only while we are still checking.
      // Once `profileChecked` is true, we redirect away below.
      if (path == '/gate' && !authProvider.profileChecked) return null;

      if (!isLoggedIn) {
        if (path == '/role') return null;
        if (!isAuthRoute) return '/role';
        return null;
      }

      // Logged in, but registration status not loaded yet.
      if (!authProvider.profileChecked) return '/gate';

      final role = authProvider.role;
      final isDoctorDashboard = path == '/doctor-dashboard';
      final isDoctorOnboardingRoute = path == '/doctor-onboarding';
      final isPatientDashboardRoute = path == '/dashboard';
      final isPatientDetailsRoute = path == '/patient-details';

      // Always allow role selection page from intro Skip or manual navigation.
      if (path == '/role') return null;

      // Patient-only feature routes
      final isPatientFeatureRoute = path.startsWith('/my-appointments') ||
          path.startsWith('/my-report') ||
          {
            '/dashboard',
            '/my-scans',
            '/doctors',
            '/scalp-analyzer',
            '/graft-result',
            '/recommendations',
            '/guidelines',
            '/reports',
            '/appointment',
          }.contains(path);

      // Doctor-only feature routes
      final isDoctorFeatureRoute = {
        '/doctor-dashboard',
        '/doctor-appointments',
        '/doctor-patients',
        '/doctor-profile',
        '/doctor-onboarding',
      }.contains(path);

      // Enforce profile completion: doctors finish [DoctorProfileRegistrationScreen] before dashboard.
      // Always allow role login routes so doctor login shows sign-in, not forced signup.
      final isDoctorSignupRoute = path == '/signup/doctor';
      final isDoctorLoginRoute = path == '/login/doctor';
      if (role == 'doctor' && !authProvider.isDoctorRegistered) {
        if (isDoctorOnboardingRoute || isDoctorSignupRoute || isDoctorLoginRoute) {
          return null;
        }
        // Already signed in as a doctor but profile not finished — go to onboarding, not signup.
        return '/doctor-onboarding';
      }

      final isPatientLoginRoute = path == '/login/patient';
      final isPatientSignupRoute = path == '/signup/patient';
      if (role == 'patient' && !authProvider.isPatientRegistered) {
        if (isPatientDetailsRoute || isPatientLoginRoute || isPatientSignupRoute) {
          return null;
        }
        return '/patient-details';
      }

      // Enforce role-based route access.
      if (role == 'doctor' && isPatientFeatureRoute) return '/doctor-dashboard';
      if (role == 'patient' && isDoctorFeatureRoute) return '/dashboard';

      // Keep dashboard paths consistent.
      if (role == 'doctor' && isPatientDashboardRoute) return '/doctor-dashboard';
      if (role == 'patient' && isDoctorDashboard) return '/dashboard';

      // Gate is temporary: once status is known, send user to the right home.
      if (path == '/gate') {
        if (role == 'doctor') {
          return authProvider.isDoctorRegistered ? '/doctor-dashboard' : '/doctor-onboarding';
        }
        return authProvider.isPatientRegistered ? '/dashboard' : '/patient-details';
      }

      // Default: allow.
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/role',
        builder: (_, __) => const RoleSelectionScreen(),
      ),
      GoRoute(
        path: '/login/patient',
        builder: (_, __) => const LoginScreen(role: 'patient'),
      ),
      GoRoute(
        path: '/login/doctor',
        builder: (_, __) => const LoginScreen(role: 'doctor'),
      ),
      GoRoute(
        path: '/signup/patient',
        builder: (_, __) => const SignupPatientScreen(),
      ),
      GoRoute(
        path: '/signup/doctor',
        builder: (_, __) => const SignupDoctorScreen(),
      ),
      GoRoute(
        path: '/patient-details',
        builder: (_, __) => const PatientDetailsScreen(),
      ),
      GoRoute(
        path: '/appointment',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return AppointmentScreen(
            doctorId: extra?['doctorId']?.toString(),
            doctorName: extra?['doctorName']?.toString(),
            clinicName: extra?['clinicName']?.toString(),
          );
        },
      ),
      GoRoute(
        path: '/doctors',
        builder: (_, __) => const DoctorListScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) =>
            kIsWeb ? const PatientDashboardWeb() : const MobileDashboardScreen(),
      ),
      GoRoute(
        path: '/my-scans',
        builder: (_, __) =>
            kIsWeb ? const PatientMyScansWeb() : const PatientMyScansScreen(),
      ),
      GoRoute(
        path: '/my-appointments',
        builder: (_, __) => kIsWeb
            ? const PatientMyAppointmentsWeb()
            : const PatientMyAppointmentsScreen(),
      ),
      GoRoute(
        path: '/my-appointments/book',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? const {};
          final feeRaw = extra['consultationFeePkr'] ?? extra['fee'];
          return PatientAppointmentBookingScreen(
            doctorName: (extra['doctorName'] ?? 'Selected Doctor').toString(),
            doctorId: extra['doctorId']?.toString(),
            clinicName: extra['clinicName']?.toString(),
            city: extra['city']?.toString(),
            consultationFeePkr: feeRaw is num ? feeRaw.toInt() : int.tryParse(feeRaw?.toString() ?? ''),
          );
        },
      ),
      GoRoute(
        path: '/my-appointments/success',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? const {};
          return PatientAppointmentSuccessScreen(
            doctorName: (extra['doctorName'] ?? 'Selected Doctor').toString(),
            date: (extra['date'] ?? '-').toString(),
            time: (extra['time'] ?? '-').toString(),
            doctorId: extra['doctorId']?.toString(),
            reminder: extra['reminder']?.toString(),
          );
        },
      ),
      GoRoute(
        path: '/my-report',
        builder: (_, __) =>
            kIsWeb ? const PatientMyReportWeb() : const PatientMyReportScreen(),
      ),
      GoRoute(
        path: '/my-report/view/:reportId',
        builder: (_, state) {
          final id = state.pathParameters['reportId'] ?? '';
          return ScalpReportDetailScreen(reportId: id);
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/profile',
        builder: (_, __) => const PatientProfileEditScreen(),
      ),
      GoRoute(
        path: '/settings/clinic-details',
        builder: (_, __) => const ClinicDetailsScreen(),
      ),
      GoRoute(
        path: '/settings/notifications',
        builder: (_, __) => const NotificationsSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/about',
        builder: (_, __) => const AboutUsScreen(),
      ),
      GoRoute(
        path: '/change-password',
        builder: (_, __) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: '/doctor-dashboard',
        builder: (_, __) =>
            kIsWeb ? const DoctorDashboardWeb() : const DoctorDashboardScreen(),
      ),
      GoRoute(
        path: '/doctor-appointments',
        builder: (_, __) => kIsWeb
            ? const DoctorDashboardWeb(section: 'appointments')
            : const DoctorDashboardScreen(section: 'appointments'),
      ),
      GoRoute(
        path: '/doctor-patients',
        builder: (_, __) => kIsWeb
            ? const DoctorDashboardWeb(section: 'patients')
            : const DoctorDashboardScreen(section: 'patients'),
      ),
      GoRoute(
        path: '/doctor-profile',
        builder: (_, __) => const DoctorProfileEditScreen(),
      ),
      GoRoute(
        path: '/doctor-onboarding',
        builder: (_, __) => const DoctorProfileRegistrationScreen(),
      ),
      GoRoute(
        path: '/gate',
        builder: (_, __) => const GateScreen(),
      ),
      GoRoute(
        path: '/scalp-analyzer',
        builder: (_, __) => const ScalpAnalyzerScreen(),
      ),
      GoRoute(
        path: '/graft-result',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          int? intExtra(dynamic v) {
            if (v == null) return null;
            if (v is int) return v;
            if (v is num) return v.round();
            return int.tryParse(v.toString());
          }

          Map<String, String>? b;
          final raw = extra?['breakdown'];
          if (raw is Map) {
            b = raw.map((k, v) => MapEntry(k.toString(), v.toString()));
          }

          return GraftResultScreen(
            totalMin: intExtra(extra?['totalMin']),
            totalMax: intExtra(extra?['totalMax']),
            overlayImageBase64: extra?['overlayImageBase64']?.toString(),
            breakdown: b,
          );
        },
      ),
      GoRoute(
        path: '/recommendations',
        builder: (context, state) {
          ScalpAnalysisModel? analysis;
          try {
            final extra = state.extra;
            if (extra is Map<String, dynamic>) {
              analysis = extra['analysis'] as ScalpAnalysisModel?;
            }
          } catch (_) {}
          return RecommendationsScreen(analysis: analysis);
        },
      ),
      GoRoute(
        path: '/guidelines',
        builder: (_, __) => const GuidelinesScreen(),
      ),
      GoRoute(
        path: '/reports',
        builder: (_, __) => const ReportsScreen(),
      ),
    ],
  );
}
