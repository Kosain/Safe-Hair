import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_colors.dart';
import '../../core/validators.dart';
import '../../providers/auth_provider.dart';
import '../../services/firebase_service.dart';
import '../../widgets/animated_primary_button.dart';
import '../../widgets/firebase_init_banner.dart';
import '../../widgets/safe_hair_auth_shell.dart';

class SignupPatientScreen extends StatefulWidget {
  const SignupPatientScreen({super.key});

  @override
  State<SignupPatientScreen> createState() => _SignupPatientScreenState();
}

class _SignupPatientScreenState extends State<SignupPatientScreen> {
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
      context.read<AuthProvider>().setRole('patient');
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeHairAuthShell(
      title: 'Sign up as Patient',
      subtitle: 'Create your account to access personalized hair and scalp care.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FirebaseInitBanner(),
          const SizedBox(height: 12),
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
                  onPressed: _loading ? null : _handleSignUp,
                  height: 52,
                  borderRadius: 30,
                  gradientColors: const [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Create patient account', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
              onTap: () => context.go('/login/patient'),
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

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to the Terms of Service & Privacy Policy.')),
      );
      return;
    }
    setState(() => _loading = true);
    final success = await context.read<AuthProvider>().signUpWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
          name: _emailController.text.trim().split('@').first,
        );
    if (mounted) {
      setState(() => _loading = false);
      if (success) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/patient-details');
        });
      } else {
        final msg = context.read<AuthProvider>().lastAuthError ?? 'Could not create account. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _handleGoogleSignUp() async {
    setState(() => _loading = true);
    final success = await context.read<AuthProvider>().signInWithGoogle();
    if (mounted) {
      setState(() => _loading = false);
      if (success) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/patient-details');
        });
      } else {
        final msg = FirebaseService.lastAuthError ??
            'Google sign-up failed. Enable Google sign-in in Firebase Console and add your domain under Authentication → Settings → Authorized domains.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _handleFacebookSignUp() async {
    setState(() => _loading = true);
    final success = await context.read<AuthProvider>().signInWithFacebook();
    if (mounted) {
      setState(() => _loading = false);
      if (success) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/patient-details');
        });
      } else {
        final msg = FirebaseService.lastAuthError ??
            'Facebook sign-up failed. Enable the Facebook provider in Firebase Console.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }
}
