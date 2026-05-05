import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';

class PatientProfileEditScreen extends StatefulWidget {
  const PatientProfileEditScreen({super.key});

  @override
  State<PatientProfileEditScreen> createState() => _PatientProfileEditScreenState();
}

class _PatientProfileEditScreenState extends State<PatientProfileEditScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _picker = ImagePicker();

  Uint8List? _profileImageBytes;
  String? _profileImageUrl;
  DateTime? _dob;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = context.read<AuthProvider>().userId;
    if (uid == null || !FirebaseService.isInitialized) {
      setState(() => _loading = false);
      return;
    }
    final snap = await FirebaseService.getPatientDetails(uid);
    if (!mounted) return;
    if (snap != null && snap.exists) {
      final d = snap.data()!;
      _nameController.text = d['name']?.toString() ?? '';
      _phoneController.text = d['mobile']?.toString() ?? '';
      _addressController.text = d['address']?.toString() ?? '';
      final day = (d['dob_day'] as num?)?.toInt() ?? (d['age_day'] as num?)?.toInt();
      final month = (d['dob_month'] as num?)?.toInt() ?? (d['age_month'] as num?)?.toInt();
      final year = (d['dob_year'] as num?)?.toInt() ?? (d['age_year'] as num?)?.toInt();
      if (day != null && month != null && year != null) {
        _dob = DateTime(year, month, day);
      }
      _profileImageUrl = d['profileImageUrl']?.toString();
      final b64 = d['profileImageBase64']?.toString();
      if (b64 != null && b64.isNotEmpty) {
        try {
          _profileImageBytes = base64Decode(b64);
        } catch (_) {}
      }
    }
    setState(() => _loading = false);
  }

  Future<void> _pickImage(ImageSource source) async {
    final xFile = await _picker.pickImage(source: source, maxWidth: 900);
    if (xFile == null) return;
    final bytes = await xFile.readAsBytes();
    if (!mounted) return;
    setState(() => _profileImageBytes = bytes);
    context.read<AuthProvider>().setUserPhoto(bytes: bytes);
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = _dob ?? DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    final uid = context.read<AuthProvider>().userId;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in.')),
      );
      return;
    }
    if (!FirebaseService.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Firebase is not available.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      String? imageUrl = _profileImageUrl;
      if (_profileImageBytes != null) {
        try {
          imageUrl = await FirebaseService.uploadImage(
            'patients/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
            _profileImageBytes!,
          ).timeout(const Duration(seconds: 20));
        } catch (_) {}
      }

      final bytes = _profileImageBytes;
      final String? profileB64 =
          (bytes != null && bytes.length <= 400000) ? base64Encode(bytes) : null;

      final dob = _dob;
      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        'mobile': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        if (imageUrl != null) 'profileImageUrl': imageUrl,
        if (profileB64 != null) 'profileImageBase64': profileB64,
        if (dob != null) ...{
          'dob_day': dob.day,
          'dob_month': dob.month,
          'dob_year': dob.year,
          'age_day': dob.day,
          'age_month': dob.month,
          'age_year': dob.year,
        },
      };

      final saved = await FirebaseService.savePatientDetails(data);
      if (!mounted) return;
      if (saved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(FirebaseService.lastPatientSaveError ?? 'Could not save profile.'),
          ),
        );
        return;
      }

      if (_nameController.text.trim().isNotEmpty) {
        context.read<AuthProvider>().setUserProfile(_nameController.text.trim());
      }
      if (imageUrl != null && imageUrl.isNotEmpty) {
        context.read<AuthProvider>().setUserPhoto(url: imageUrl);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved')),
      );
      context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF7F7F7),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final dobLabel = _dob != null
        ? '${_dob!.day.toString().padLeft(2, '0')} ${_monthName(_dob!.month)} ${_dob!.year}'
        : 'DD MM YYYY';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'Set up your profile',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Update your profile to connect your doctor with better impression.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.35),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: _showImageSourceSheet,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade300, width: 2),
                          ),
                          child: CircleAvatar(
                            radius: 52,
                            backgroundColor: Colors.white,
                            backgroundImage: _profileImageBytes != null
                                ? MemoryImage(_profileImageBytes!)
                                : (_profileImageUrl != null && _profileImageUrl!.isNotEmpty
                                    ? NetworkImage(_profileImageUrl!)
                                    : null),
                            child: (_profileImageBytes == null &&
                                    (_profileImageUrl == null || _profileImageUrl!.isEmpty))
                                ? Icon(Icons.person, size: 52, color: Colors.grey.shade500)
                                : null,
                          ),
                        ),
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade700,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Personal information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black),
            ),
            const SizedBox(height: 16),
            _LabeledFieldCard(
              label: 'Name',
              child: TextField(
                controller: _nameController,
                style: const TextStyle(fontSize: 16, color: Colors.black),
                decoration: _profileFieldDecoration(),
              ),
            ),
            const SizedBox(height: 12),
            _LabeledFieldCard(
              label: 'Contact Number',
              trailing: Icon(Icons.edit_outlined, size: 18, color: Colors.grey.shade700),
              child: TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 16, color: Colors.black),
                decoration: _profileFieldDecoration(),
              ),
            ),
            const SizedBox(height: 12),
            _LabeledFieldCard(
              label: 'Date of birth',
              trailing: Icon(Icons.edit_outlined, size: 18, color: Colors.grey.shade700),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: _pickDob,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: Text(
                      dobLabel,
                      style: TextStyle(
                        fontSize: 16,
                        color: _dob != null ? Colors.black : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _LabeledFieldCard(
              label: 'Address',
              child: TextField(
                controller: _addressController,
                maxLines: 4,
                style: const TextStyle(fontSize: 16, color: Colors.black),
                decoration: _profileFieldDecoration(
                  hint: 'Add details',
                ),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static InputDecoration _profileFieldDecoration({String? hint}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade400),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade500),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.black87, width: 1.2),
      ),
    );
  }

  String _monthName(int m) {
    const names = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[m.clamp(1, 12)];
  }
}

class _LabeledFieldCard extends StatelessWidget {
  const _LabeledFieldCard({
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
