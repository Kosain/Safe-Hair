import 'package:firebase_auth/firebase_auth.dart'
    show EmailAuthProvider, FirebaseAuth, FirebaseAuthException;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/safe_hair_colors.dart';
import '../l10n/tr.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../services/firebase_service.dart';
import '../widgets/preference_picker_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Future<void> _pickLanguage(BuildContext context) async {
    final locale = context.read<LocaleProvider>();
    final picked = await showPreferencePickerDialog(
      context: context,
      titleKey: 'select_language',
      currentValue: locale.languageCode,
      options: const [('en', 'english'), ('ur', 'urdu')],
    );
    if (picked == null || !context.mounted) return;
    await locale.setLocale(Locale(picked));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('language_updated'))),
      );
    }
  }

  static Future<void> _pickTheme(BuildContext context) async {
    final theme = context.read<ThemeProvider>();
    final current = theme.isDark ? 'dark' : 'light';
    final picked = await showPreferencePickerDialog(
      context: context,
      titleKey: 'select_theme',
      currentValue: current,
      options: const [('light', 'light'), ('dark', 'dark')],
    );
    if (picked == null || !context.mounted) return;
    await theme.setThemeMode(picked == 'dark' ? ThemeMode.dark : ThemeMode.light);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('theme_updated'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDoctor = auth.role == 'doctor';
    final sh = context.sh;

    final tiles = <Widget>[
      if (isDoctor) ...[
        _SettingsNavTile(
          icon: Icons.person,
          titleKey: 'profile',
          onTap: () => context.push('/doctor-profile'),
        ),
        _SettingsNavTile(
          icon: Icons.business,
          titleKey: 'clinic_details',
          onTap: () => context.push('/settings/clinic-details'),
        ),
      ] else ...[
        _SettingsNavTile(
          icon: Icons.person,
          titleKey: 'profile',
          onTap: () => context.push('/settings/profile'),
        ),
      ],
      _SettingsNavTile(
        icon: Icons.lock,
        titleKey: 'change_password',
        onTap: () => context.push('/change-password'),
      ),
      _SettingsNavTile(
        icon: Icons.notifications,
        titleKey: 'notifications',
        onTap: () => context.push('/settings/notifications'),
      ),
      _SettingsNavTile(
        icon: Icons.language,
        titleKey: 'language',
        onTap: () => _pickLanguage(context),
      ),
      _SettingsNavTile(
        icon: Icons.brightness_6,
        titleKey: 'theme',
        onTap: () => _pickTheme(context),
      ),
      _SettingsNavTile(
        icon: Icons.info,
        titleKey: 'about_us',
        onTap: () => context.push('/settings/about'),
      ),
    ];

    return Scaffold(
      backgroundColor: sh.scaffold,
      appBar: AppBar(
        backgroundColor: sh.appBar,
        surfaceTintColor: sh.appBar,
        elevation: 0,
        title: Text(
          context.t('settings'),
          style: TextStyle(color: sh.textPrimary, fontWeight: FontWeight.w600, fontSize: 19),
        ),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: Icon(Icons.arrow_back_ios_new, color: sh.textPrimary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: tiles,
      ),
    );
  }
}

class _SettingsNavTile extends StatelessWidget {
  const _SettingsNavTile({
    required this.icon,
    required this.titleKey,
    required this.onTap,
  });

  final IconData icon;
  final String titleKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: sh.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sh.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(icon, color: sh.textSecondary, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    context.t(titleKey),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: sh.textPrimary,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: sh.textSecondary, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() => _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState extends State<NotificationsSettingsScreen> {
  bool _incomingRequests = true;
  bool _appointmentReminders = true;
  bool _systemAnnouncements = true;

  bool _scanReminder = true;
  bool _appointmentReminder = true;
  bool _newReportReady = true;
  bool _aiDailyTips = true;

  @override
  Widget build(BuildContext context) {
    final isDoctor = context.watch<AuthProvider>().role == 'doctor';
    final sh = context.sh;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final switchTheme = SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackOutlineColor: WidgetStateProperty.all(isDark ? sh.border : Colors.grey.shade500),
      trackColor: WidgetStateProperty.resolveWith(
        (s) {
          if (s.contains(WidgetState.selected)) {
            return isDark ? const Color(0xFF4DA3FF) : Colors.black;
          }
          return isDark ? const Color(0xFF3A4555) : Colors.grey.shade400;
        },
      ),
    );

    Widget row(String title, bool value, ValueChanged<bool> onChanged) {
      return SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          title,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: sh.textPrimary),
        ),
        value: value,
        onChanged: onChanged,
      );
    }

    final doctorRows = <Widget>[
      row('Incoming Appointment Requests', _incomingRequests, (v) => setState(() => _incomingRequests = v)),
      Divider(height: 1, thickness: 1, color: sh.border),
      row('Appointment Reminders', _appointmentReminders, (v) => setState(() => _appointmentReminders = v)),
      Divider(height: 1, thickness: 1, color: sh.border),
      row('System & Announcements', _systemAnnouncements, (v) => setState(() => _systemAnnouncements = v)),
    ];

    final patientRows = <Widget>[
      row('Scan Reminder', _scanReminder, (v) => setState(() => _scanReminder = v)),
      Divider(height: 1, thickness: 1, color: sh.border),
      row('Appointment Reminder', _appointmentReminder, (v) => setState(() => _appointmentReminder = v)),
      Divider(height: 1, thickness: 1, color: sh.border),
      row('New Report Ready', _newReportReady, (v) => setState(() => _newReportReady = v)),
      Divider(height: 1, thickness: 1, color: sh.border),
      row('AI Daily Tips', _aiDailyTips, (v) => setState(() => _aiDailyTips = v)),
    ];

    return Theme(
      data: Theme.of(context).copyWith(switchTheme: switchTheme),
      child: Scaffold(
        backgroundColor: sh.scaffold,
        appBar: AppBar(
          backgroundColor: sh.appBar,
          surfaceTintColor: sh.appBar,
          elevation: 0,
          leading: IconButton(
            onPressed: () => context.pop(),
            icon: Icon(Icons.arrow_back_ios_new, color: sh.textPrimary),
          ),
          title: Text(
            context.t('notification_preferences'),
            style: TextStyle(color: sh.textPrimary, fontWeight: FontWeight.w600, fontSize: 19),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              color: sh.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: sh.border),
              ),
              child: Column(
                children: isDoctor ? doctorRows : patientRows,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _newPass = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _newPass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, bool obscure, VoidCallback toggleObscure) {
    final sh = context.sh;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: sh.textPrimary),
      filled: true,
      fillColor: sh.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      suffixIcon: IconButton(
        icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: sh.textSecondary),
        onPressed: toggleObscure,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: sh.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: sh.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: sh.textPrimary, width: 1.2),
      ),
    );
  }

  Future<void> _submit() async {
    final cur = _current.text;
    final nw = _newPass.text.trim();
    final cf = _confirm.text.trim();

    if (cur.isEmpty || nw.isEmpty || cf.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All fields are required.')),
      );
      return;
    }
    if (nw.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New password must be at least 6 characters.')),
      );
      return;
    }
    if (nw != cf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New password and confirmation do not match.')),
      );
      return;
    }

    if (!FirebaseService.isInitialized) {
      if (cur != '123456') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Current password is incorrect.')),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed successfully.')),
      );
      context.pop();
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password change is only available for email sign-in accounts.'),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final cred = EmailAuthProvider.credential(email: email, password: cur);
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(nw);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed successfully.')),
      );
      context.pop();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg = 'Could not update password. Try again.';
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          msg = 'Current password is incorrect.';
          break;
        case 'weak-password':
          msg = 'New password is too weak.';
          break;
        case 'requires-recent-login':
          msg = 'Please sign out and sign in again, then try changing your password.';
          break;
        default:
          msg = e.message ?? msg;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    return Scaffold(
      backgroundColor: sh.scaffold,
      appBar: AppBar(
        backgroundColor: sh.appBar,
        surfaceTintColor: sh.appBar,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: Icon(Icons.arrow_back_ios_new, color: sh.textPrimary),
        ),
        title: Text(
          context.t('change_password'),
          style: TextStyle(color: sh.textPrimary, fontWeight: FontWeight.w600, fontSize: 19),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 0,
          color: sh.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: sh.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _current,
                  obscureText: _obscureCurrent,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: sh.textPrimary),
                  decoration: _decoration('Current Password', _obscureCurrent, () => setState(() => _obscureCurrent = !_obscureCurrent)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _newPass,
                  obscureText: _obscureNew,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: sh.textPrimary),
                  decoration: _decoration('New Password (min 6 characters)', _obscureNew, () => setState(() => _obscureNew = !_obscureNew)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _confirm,
                  obscureText: _obscureConfirm,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: sh.textPrimary),
                  decoration: _decoration('Confirm New Password', _obscureConfirm, () => setState(() => _obscureConfirm = !_obscureConfirm)),
                ),
                const SizedBox(height: 22),
                Center(
                  child: ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: sh.selectedNavBg,
                      foregroundColor: sh.selectedNavFg,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _busy
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: sh.selectedNavFg),
                          )
                        : Text(context.t('change_password'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _SimpleSettingsPlaceholder(
      titleKey: 'about_us',
      description: 'Safe Hair v1.0.0\nAI-assisted scalp analysis and guidance.',
    );
  }
}

class _SimpleSettingsPlaceholder extends StatelessWidget {
  const _SimpleSettingsPlaceholder({
    required this.titleKey,
    required this.description,
  });

  final String titleKey;
  final String description;

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    return Scaffold(
      backgroundColor: sh.scaffold,
      appBar: AppBar(
        backgroundColor: sh.appBar,
        surfaceTintColor: sh.appBar,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: Icon(Icons.arrow_back_ios_new, color: sh.textPrimary),
        ),
        title: Text(
          context.t(titleKey),
          style: TextStyle(color: sh.textPrimary, fontWeight: FontWeight.w600, fontSize: 19),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(color: sh.textPrimary, fontSize: 16, fontWeight: FontWeight.w500, height: 1.4),
          ),
        ),
      ),
    );
  }
}
