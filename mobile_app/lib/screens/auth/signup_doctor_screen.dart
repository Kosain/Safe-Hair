import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../core/validators.dart';
import '../../providers/auth_provider.dart';
import '../../services/firebase_service.dart';
import '../../widgets/animated_primary_button.dart';
import '../../widgets/safe_hair_auth_shell.dart';

class SignupDoctorScreen extends StatefulWidget {
  const SignupDoctorScreen({super.key});

  @override
  State<SignupDoctorScreen> createState() => _SignupDoctorScreenState();
}

class _SignupDoctorScreenState extends State<SignupDoctorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreeToTerms = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthProvider>().setRole('doctor');
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeHairAuthShell(
      title: 'Sign up as Doctor',
      subtitle: 'Join us as a verified specialist\nProvide diagnosis and expert recommendations',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AuthSocialButton(
                label: 'Google',
                onTap: _loading ? () {} : _handleGoogleSignUp,
                leading: Image.asset('assets/Vector.png', width: 20, height: 20, fit: BoxFit.contain),
                gradientColors: const [Colors.white, Colors.white],
                textColor: AppColors.textDark,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
                borderSide: const BorderSide(color: Color(0x1F000000), width: 1),
              ),
              const SizedBox(width: 12),
              AuthSocialButton(
                label: 'Facebook',
                onTap: _loading ? () {} : _handleFacebookSignUp,
                leading: const Icon(Icons.facebook, size: 22, color: Color(0xFF35539C)),
                gradientColors: const [Colors.white, Colors.white],
                textColor: AppColors.textDark,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
                borderSide: const BorderSide(color: Color(0x1F000000), width: 1),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.black),
                  cursorColor: AppColors.darkButton,
                  decoration: safeHairAuthInputDecoration(hint: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: validateEmail,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordController,
                  style: const TextStyle(color: Colors.black),
                  obscureText: _obscurePassword,
                  cursorColor: AppColors.darkButton,
                  decoration: safeHairAuthInputDecoration(
                    hint: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppColors.textGrey,
                        size: 22,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: validateStrongPassword,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmPasswordController,
                  style: const TextStyle(color: Colors.black),
                  obscureText: _obscureConfirmPassword,
                  cursorColor: AppColors.darkButton,
                  decoration: safeHairAuthInputDecoration(
                    hint: 'Confirm password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppColors.textGrey,
                        size: 22,
                      ),
                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                  ),
                  validator: (v) {
                    final err = validatePasswordRequired(v);
                    if (err != null) return err;
                    if (v != _passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Transform.scale(
                      scale: 0.92,
                      child: Checkbox(
                        value: _agreeToTerms,
                        onChanged: _loading ? null : (v) => setState(() => _agreeToTerms = v ?? false),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        activeColor: Colors.black,
                        checkColor: Colors.white,
                        side: BorderSide(color: Colors.black.withValues(alpha: 0.5), width: 1.4),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: _loading ? null : () => setState(() => _agreeToTerms = !_agreeToTerms),
                        child: const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Text(
                            'I agree with the Terms of Service & Privacy Policy',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textGrey,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                AnimatedPrimaryButton(
                  onPressed: _loading ? null : _handleEmailSignup,
                  height: 52,
                  borderRadius: 30,
                  gradientColors: const [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Create doctor account', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ],
            ),
          ),
        ],
      ),
      footer: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Already have an account? ',
              style: TextStyle(color: AppColors.textGrey.withValues(alpha: 0.95), fontSize: 14),
            ),
            GestureDetector(
              onTap: () => context.go('/login/doctor'),
              child: const Text(
                'Login',
                style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textDark, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleEmailSignup() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to the Terms of Service & Privacy Policy.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthProvider>();
      final success = await auth.signUpWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
        name: _emailController.text.trim().split('@').first,
      );

      if (!mounted) return;
      if (success && auth.userId != null) {
        await _saveMinimalDoctorProfile(auth);
        await auth.refreshRegistrationStatus();
        if (!mounted) return;
        context.go('/doctor-onboarding');
      } else {
        final msg = auth.lastAuthError ?? 'Could not create account. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleGoogleSignUp() async {
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthProvider>();
      final success = await auth.signInWithGoogle();
      if (!mounted) return;
      if (success && auth.userId != null) {
        auth.setRole('doctor');
        await _saveMinimalDoctorProfile(auth);
        await auth.refreshRegistrationStatus();
        if (!mounted) return;
        context.go('/doctor-onboarding');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Google sign-up failed. Enable in Firebase Console.')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleFacebookSignUp() async {
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthProvider>();
      final success = await auth.signInWithFacebook();
      if (!mounted) return;
      if (success && auth.userId != null) {
        auth.setRole('doctor');
        await _saveMinimalDoctorProfile(auth);
        await auth.refreshRegistrationStatus();
        if (!mounted) return;
        context.go('/doctor-onboarding');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Facebook sign-up failed. Enable in Firebase Console.')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Stub document so login checks see a doctor row; full details are collected on [DoctorProfileRegistrationScreen].
  Future<void> _saveMinimalDoctorProfile(AuthProvider auth) async {
    if (!FirebaseService.isInitialized || auth.userId == null) return;
    final email = auth.userEmail ?? _emailController.text.trim();
    final ok = await FirebaseService.saveDoctorProfile({
      'userId': auth.userId!,
      'role': 'doctor',
      'fullName': auth.userName ?? email.split('@').first,
      'email': email,
      'profileCompleted': false,
    }).timeout(
      const Duration(seconds: 18),
      onTimeout: () {
        FirebaseService.lastDoctorProfileSaveError =
            FirebaseService.lastDoctorProfileSaveError ??
            'Saving your profile timed out. Check internet and Firestore rules, then continue onboarding.';
        return false;
      },
    );
    if (!ok && mounted) {
      final err = FirebaseService.lastDoctorProfileSaveError ?? 'Could not save starter profile.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$err You can still fill in details — save again at the end.')),
      );
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
