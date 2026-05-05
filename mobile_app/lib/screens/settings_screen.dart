import 'package:firebase_auth/firebase_auth.dart'
    show EmailAuthProvider, FirebaseAuth, FirebaseAuthException;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static void _comingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDoctor = auth.role == 'doctor';

    final tiles = <Widget>[
      if (isDoctor) ...[
        _SettingsNavTile(
          icon: Icons.business,
          title: 'Clinic Details',
          onTap: () => context.push('/settings/clinic-details'),
        ),
      ] else ...[
        _SettingsNavTile(
          icon: Icons.person,
          title: 'Profile',
          onTap: () => context.push('/settings/profile'),
        ),
      ],
      _SettingsNavTile(
        icon: Icons.lock,
        title: 'Change Password',
        onTap: () => context.push('/change-password'),
      ),
      _SettingsNavTile(
        icon: Icons.notifications,
        title: 'Notifications',
        onTap: () => context.push('/settings/notifications'),
      ),
      _SettingsNavTile(
        icon: Icons.language,
        title: 'Language',
        onTap: () => _comingSoon(context, 'Language'),
      ),
      _SettingsNavTile(
        icon: Icons.brightness_6,
        title: 'Theme',
        onTap: () => _comingSoon(context, 'Theme'),
      ),
      _SettingsNavTile(
        icon: Icons.info,
        title: 'About us',
        onTap: () => _comingSoon(context, 'About us'),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 19),
        ),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
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
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
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
                Icon(icon, color: Colors.black54, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey.shade600, size: 22),
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

    final switchTheme = SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.black : Colors.grey.shade400,
      ),
    );

    Widget row(String title, bool value, ValueChanged<bool> onChanged) {
      return SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
        ),
        value: value,
        onChanged: onChanged,
      );
    }

    final doctorRows = <Widget>[
      row('Incoming Appointment Requests', _incomingRequests, (v) => setState(() => _incomingRequests = v)),
      Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
      row('Appointment Reminders', _appointmentReminders, (v) => setState(() => _appointmentReminders = v)),
      Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
      row('System & Announcements', _systemAnnouncements, (v) => setState(() => _systemAnnouncements = v)),
    ];

    final patientRows = <Widget>[
      row('Scan Reminder', _scanReminder, (v) => setState(() => _scanReminder = v)),
      Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
      row('Appointment Reminder', _appointmentReminder, (v) => setState(() => _appointmentReminder = v)),
      Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
      row('New Report Ready', _newReportReady, (v) => setState(() => _newReportReady = v)),
      Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
      row('AI Daily Tips', _aiDailyTips, (v) => setState(() => _aiDailyTips = v)),
    ];

    return Theme(
      data: Theme.of(context).copyWith(switchTheme: switchTheme),
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          ),
          title: const Text(
            'Notification Preferences',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 19),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
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
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      suffixIcon: IconButton(
        icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.black54),
        onPressed: toggleObscure,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.black, width: 1.2),
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
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
        ),
        title: const Text(
          'Change Password',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 19),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _current,
                  obscureText: _obscureCurrent,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  decoration: _decoration('Current Password', _obscureCurrent, () => setState(() => _obscureCurrent = !_obscureCurrent)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _newPass,
                  obscureText: _obscureNew,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  decoration: _decoration('New Password (min 6 characters)', _obscureNew, () => setState(() => _obscureNew = !_obscureNew)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _confirm,
                  obscureText: _obscureConfirm,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  decoration: _decoration('Confirm New Password', _obscureConfirm, () => setState(() => _obscureConfirm = !_obscureConfirm)),
                ),
                const SizedBox(height: 22),
                Center(
                  child: ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Change Password', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
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
    return const _SimpleSettingsPlaceholder(
      title: 'About us',
      description: 'Safe Hair v1.0.0\nAI-assisted scalp analysis and guidance.',
    );
  }
}

class _SimpleSettingsPlaceholder extends StatelessWidget {
  const _SimpleSettingsPlaceholder({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
        ),
        title: Text(
          title,
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 19),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w500, height: 1.4),
          ),
        ),
      ),
    );
  }
}
