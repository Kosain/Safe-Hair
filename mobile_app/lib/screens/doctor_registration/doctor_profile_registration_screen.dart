import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/doctor_registration_provider.dart';
import '../../services/firebase_service.dart';
import 'consultant_registration_ui.dart';
import 'steps/dr_consultant_step1_profile.dart';
import 'steps/dr_consultant_step2_personal.dart';
import 'steps/dr_consultant_step3_expertise.dart';
import 'steps/dr_consultant_step4_clinic.dart';
import 'steps/dr_consultant_step5_documents.dart';
import 'steps/dr_consultant_step6_availability.dart';

/// Six-step consultant (single-doctor) registration — replaces legacy clinic onboarding.
class DoctorProfileRegistrationScreen extends StatefulWidget {
  const DoctorProfileRegistrationScreen({super.key});

  @override
  State<DoctorProfileRegistrationScreen> createState() => _DoctorProfileRegistrationScreenState();
}

class _DoctorProfileRegistrationScreenState extends State<DoctorProfileRegistrationScreen> {
  bool _actionBusy = false;

  @override
  void initState() {
    super.initState();
    context.read<DoctorRegistrationProvider>().reset(notify: false);
  }

  static const _stepTitles = [
    'Profile',
    'Personal details',
    'Expertise',
    'Practice',
    'Documents',
    'Availability',
  ];

  Future<void> _onContinue() async {
    final auth = context.read<AuthProvider>();
    final p = context.read<DoctorRegistrationProvider>();
    if (auth.userId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in again.')));
      return;
    }

    if (!p.tryAdvanceStep()) {
      if (mounted) {
        final msg = p.fieldErrors.values.isNotEmpty ? p.fieldErrors.values.first : 'Please fix the highlighted fields.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _onFinish() async {
    final auth = context.read<AuthProvider>();
    final p = context.read<DoctorRegistrationProvider>();
    final uid = auth.userId;
    if (uid == null) return;

    final err = p.validateStep(5);
    if (err != null) {
      p.refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
      return;
    }

    setState(() {
      _actionBusy = true;
      p.submitting = true;
    });
    p.refresh();

    final email = auth.userEmail ?? '';
    final payload = p.buildFirestorePayload(uid, email);
    final ok = await FirebaseService.saveDoctorProfile(payload).timeout(
      const Duration(seconds: 45),
      onTimeout: () => false,
    );

    if (!mounted) return;
    setState(() {
      _actionBusy = false;
      p.submitting = false;
    });
    p.refresh();

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FirebaseService.lastDoctorProfileSaveError ?? 'Could not save. Check Firestore rules.')),
      );
      return;
    }

    auth.markDoctorRegistered();
    p.reset();
    if (!mounted) return;
    context.go('/doctor-dashboard');
  }

  Future<void> _onBack(DoctorRegistrationProvider p) async {
    if (p.currentStep > 0) {
      p.previousStep();
      return;
    }
    final auth = context.read<AuthProvider>();
    if (auth.isDoctorRegistered) {
      context.go('/doctor-dashboard');
    } else {
      await auth.signOut();
      if (!mounted) return;
      context.go('/role');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<DoctorRegistrationProvider>();
    final step = p.currentStep;
    final isLast = step == DoctorRegistrationProvider.totalSteps - 1;
    final busy = _actionBusy || p.submitting || (step == 0 && p.profileImageUploading);
    final step0ContinueBlocked =
        step == 0 && (!p.hasProfilePictureReady || p.profileImageUploading);

    final doctorFormTheme = Theme.of(context).copyWith(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: TextStyle(color: Colors.grey.shade600),
        labelStyle: const TextStyle(color: Color(0xFF2D2D2D)),
        floatingLabelStyle: const TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w600),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF1A1A1A), width: 1.4),
        ),
      ),
      textTheme: Theme.of(context).textTheme.apply(
        bodyColor: Colors.black,
        displayColor: Colors.black,
      ),
      primaryTextTheme: Theme.of(context).primaryTextTheme.apply(
        bodyColor: Colors.black,
        displayColor: Colors.black,
      ),
      hintColor: Colors.grey.shade600,
    );

    return Theme(
      data: doctorFormTheme,
      child: Scaffold(
      backgroundColor: AppColors.primaryGreen,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: busy
              ? null
              : () async {
                  await _onBack(p);
                },
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A1A1A), size: 20),
        ),
        title: const Text(
          'Doctor registration',
          style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w800, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Step ${step + 1} of ${DoctorRegistrationProvider.totalSteps}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF1A1A1A)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _stepTitles[step],
                      style: TextStyle(fontSize: 13, color: AppColors.textGrey.withValues(alpha: 0.9)),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (step + 1) / DoctorRegistrationProvider.totalSteps,
                        minHeight: 5,
                        backgroundColor: Colors.white.withValues(alpha: 0.65),
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: step,
                  children: [
                    const DrConsultantStep1Profile(),
                    const DrConsultantStep2Personal(),
                    const DrConsultantStep3Expertise(),
                    const DrConsultantStep4Clinic(),
                    const DrConsultantStep5Documents(),
                    const DrConsultantStep6Availability(),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: FilledButton(
                    onPressed: (busy || (!isLast && step0ContinueBlocked))
                        ? null
                        : () {
                            if (isLast) {
                              _onFinish();
                            } else {
                              _onContinue();
                            }
                          },
                    style: consultantPrimaryButtonStyle(),
                    child: busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                          )
                        : Text(
                            isLast ? 'Finish' : 'Continue',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                  ),
                ),
              ),
        ],
      ),
    ),
    );
  }
}
