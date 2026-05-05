import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_colors.dart';
import '../../core/validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/animated_primary_button.dart';
import '../../widgets/safe_hair_auth_shell.dart';

class LoginScreen extends StatefulWidget {
  final String role;

  const LoginScreen({super.key, required this.role});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthProvider>().setRole(widget.role);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPatient = widget.role == 'patient';
    final subtitle = isPatient
        ? 'Access personalized hair and scalp analysis.\nGet accurate insights and expert recommendations in one place.'
        : 'Login to manage patient consultations\nReview AI reports and guide patients';

    return SafeHairAuthShell(
      title: isPatient ? 'Login as Patient' : 'Login as Doctor',
      subtitle: subtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...[
            Row(
              children: [
                AuthSocialButton(
                  label: 'Google',
                  onTap: _loading ? () {} : _handleGoogleLogin,
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
                  onTap: _loading ? () {} : _handleFacebookLogin,
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
          ],
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.black),
                  cursorColor: AppColors.darkButton,
                  decoration: safeHairAuthInputDecoration(
                    hint: 'Email',
                  ),
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
                  validator: validatePasswordRequired,
                ),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: isPatient ? 220 : double.infinity,
                    child: AnimatedPrimaryButton(
                      onPressed: _loading ? null : _handleLogin,
                      height: 52,
                      borderRadius: 30,
                      gradientColors: const [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
                      child: _loading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              'Login',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => _showForgotPasswordModal(context),
                    child: Text(
                      'Forgot password',
                      style: TextStyle(color: AppColors.textDark.withValues(alpha: 0.75), fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      footer: Center(
        child: isPatient
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: TextStyle(color: AppColors.textGrey.withValues(alpha: 0.95), fontSize: 14),
                  ),
                  GestureDetector(
                    onTap: () => context.go('/signup/patient'),
                    child: const Text(
                      'Join us',
                      style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textDark, fontSize: 14),
                    ),
                  ),
                ],
              )
            : Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.center,
                spacing: 4,
                children: [
                  Text(
                    "Don't have an account?",
                    style: TextStyle(color: AppColors.textGrey.withValues(alpha: 0.95), fontSize: 14),
                  ),
                  GestureDetector(
                    onTap: () => context.go('/signup/doctor'),
                    child: Text(
                      'Join us',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showForgotPasswordModal(BuildContext context) {
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter your registered email address'),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: safeHairAuthInputDecoration(hint: 'Email address'),
                validator: validateEmail,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final email = emailController.text.trim();
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('OTP sent to your email (demo: 123456)')),
              );
              _showOtpDialog(context, email);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showOtpDialog(BuildContext context, String email) {
    final otpController = TextEditingController();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Verify OTP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter the 6-digit code sent to your email'),
            const SizedBox(height: 12),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: safeHairAuthInputDecoration(hint: 'OTP').copyWith(counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showForgotPasswordModal(context);
            },
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () {
              final otp = otpController.text.trim();
              if (otp != '123456') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid OTP. Try again.')),
                );
                return;
              }
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const _ChangePasswordScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final success = await auth.signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
    if (mounted) {
      setState(() => _loading = false);
      if (success) {
        await auth.refreshRegistrationStatus();
        if (!mounted) return;
        final wantsDoctor = widget.role == 'doctor';
        if (wantsDoctor) {
          if (auth.isDoctorRegistered) {
            context.go('/doctor-dashboard');
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Welcome back. Complete your clinic profile to use the doctor dashboard.',
                ),
              ),
            );
            context.go('/doctor-onboarding');
          }
        } else {
          if (auth.isPatientRegistered) {
            context.go('/dashboard');
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Patient profile not complete. Please complete registration details.'),
              ),
            );
            context.go('/patient-details');
          }
        }
      } else {
        final msg = auth.lastAuthError ?? 'Invalid email or password.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _loading = true);
    final success = await context.read<AuthProvider>().signInWithGoogle();
    if (mounted) {
      setState(() => _loading = false);
      if (success) {
        await context.read<AuthProvider>().refreshRegistrationStatus();
        if (!mounted) return;
        context.go('/gate');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Google sign-in failed. Enable Google provider in Firebase Auth and ensure web app config is correct (run flutterfire configure).',
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleFacebookLogin() async {
    setState(() => _loading = true);
    final success = await context.read<AuthProvider>().signInWithFacebook();
    if (mounted) {
      setState(() => _loading = false);
      if (success) {
        await context.read<AuthProvider>().refreshRegistrationStatus();
        if (!mounted) return;
        context.go('/gate');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Facebook sign-in failed. Enable it in Firebase Console.')),
        );
      }
    }
  }
}

class _ChangePasswordScreen extends StatefulWidget {
  const _ChangePasswordScreen();

  @override
  State<_ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<_ChangePasswordScreen> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  void _handleReset() {
    final newPass = _newPasswordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (newPass.isEmpty || confirm.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in both password fields.')),
      );
      return;
    }
    if (newPass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters.')),
      );
      return;
    }
    if (newPass != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text(
          'Password has been reset successfully! Please login with your new password.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Password'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscureNew,
                decoration: safeHairAuthInputDecoration(
                  hint: 'New Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: AppColors.textGrey,
                    ),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                decoration: safeHairAuthInputDecoration(
                  hint: 'Confirm New Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: AppColors.textGrey,
                    ),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              ElevatedButton(
                onPressed: _handleReset,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Reset Password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
