import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';

class DoctorProfileEditScreen extends StatefulWidget {
  const DoctorProfileEditScreen({super.key});

  @override
  State<DoctorProfileEditScreen> createState() => _DoctorProfileEditScreenState();
}

class _DoctorProfileEditScreenState extends State<DoctorProfileEditScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _specializationController = TextEditingController();
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
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _specializationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final uid = auth.userId;
    if (uid == null || !FirebaseService.isInitialized) {
      setState(() => _loading = false);
      return;
    }
    final d = await FirebaseService.getDoctorProfile(uid);
    if (!mounted) return;
    if (d != null) {
      _nameController.text = d['fullName']?.toString() ?? '';
      _emailController.text = d['email']?.toString() ?? auth.userEmail ?? '';
      _phoneController.text = d['phone']?.toString() ?? '';
      _addressController.text = d['address']?.toString() ?? '';
      _specializationController.text = d['specialization']?.toString() ?? '';
      final dobRaw = d['dob'];
      if (dobRaw is Timestamp) {
        _dob = dobRaw.toDate();
      }
      _profileImageUrl = d['profilePictureUrl']?.toString();
      final b64 = d['profileImageBase64']?.toString();
      if (b64 != null && b64.isNotEmpty) {
        try {
          _profileImageBytes = base64Decode(b64);
        } catch (_) {}
      }
    } else {
      _emailController.text = auth.userEmail ?? '';
    }
    setState(() => _loading = false);
  }

  Future<void> _pickImage(ImageSource source) async {
    final xFile = await _picker.pickImage(source: source, maxWidth: 900);
    if (xFile == null) return;
    final bytes = await xFile.readAsBytes();
    if (!mounted) return;
    if (bytes.length > FirebaseService.kMaxDoctorProfileImageBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image is too large. Please choose a smaller photo.')),
      );
      return;
    }
    if (!FirebaseService.isDoctorProfileImageAllowedFormat(bytes)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please use a JPEG or PNG photo.')),
      );
      return;
    }
    setState(() => _profileImageBytes = bytes);
    context.read<AuthProvider>().setUserPhoto(bytes: bytes);
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = _dob ?? DateTime(now.year - 30, now.month, now.day);
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You must be signed in.')));
      return;
    }
    if (!FirebaseService.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Firebase is not available.')));
      return;
    }

    setState(() => _saving = true);
    try {
      String? imageUrl = _profileImageUrl;
      if (_profileImageBytes != null) {
        final bytes = _profileImageBytes!;
        if (!FirebaseService.isDoctorProfileImageAllowedFormat(bytes)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please use a JPEG or PNG photo.')),
            );
          }
          return;
        }
        final t = FirebaseService.doctorProfileImageType(bytes);
        try {
          await FirebaseService.refreshAuthTokenForUpload();
          imageUrl = await FirebaseService.uploadBytes(
            'doctors/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.${t.ext}',
            bytes,
            contentType: t.contentType,
          ).timeout(const Duration(seconds: 20));
        } catch (_) {}
      }

      final bytes = _profileImageBytes;
      final String? profileB64 =
          (bytes != null && bytes.length <= 400000) ? base64Encode(bytes) : null;

      final dob = _dob;
      final data = <String, dynamic>{
        'userId': uid,
        'fullName': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'specialization': _specializationController.text.trim(),
        if (imageUrl != null && imageUrl.isNotEmpty) 'profilePictureUrl': imageUrl,
        if (profileB64 != null) 'profileImageBase64': profileB64,
        if (dob != null) 'dob': Timestamp.fromDate(dob),
      };

      final ok = await FirebaseService.saveDoctorProfile(data);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FirebaseService.lastDoctorProfileSaveError ?? 'Could not save profile.')),
        );
        return;
      }

      if (_nameController.text.trim().isNotEmpty) {
        context.read<AuthProvider>().setUserProfile(_nameController.text.trim());
      }
      if (imageUrl != null && imageUrl.isNotEmpty) {
        context.read<AuthProvider>().setUserPhoto(url: imageUrl);
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved')));
      context.go('/doctor-dashboard');
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
        : 'Tap to select';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Doctor profile', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/doctor-dashboard'),
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
                    'Personal information',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Update how patients see you in Safe Hair.',
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
            _LabeledFieldCard(
              label: 'Full name',
              child: TextField(
                controller: _nameController,
                style: const TextStyle(fontSize: 16, color: Colors.black),
                decoration: _profileFieldDecoration(),
              ),
            ),
            const SizedBox(height: 12),
            _LabeledFieldCard(
              label: 'Email',
              child: TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontSize: 16, color: Colors.black),
                decoration: _profileFieldDecoration(),
              ),
            ),
            const SizedBox(height: 12),
            _LabeledFieldCard(
              label: 'Contact number',
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
              label: 'Address (or location)',
              child: TextField(
                controller: _addressController,
                maxLines: 4,
                style: const TextStyle(fontSize: 16, color: Colors.black),
                decoration: _profileFieldDecoration(hint: 'Street, city, clinic'),
              ),
            ),
            const SizedBox(height: 12),
            _LabeledFieldCard(
              label: 'Specialization',
              child: TextField(
                controller: _specializationController,
                style: const TextStyle(fontSize: 16, color: Colors.black),
                decoration: _profileFieldDecoration(hint: 'From registration; you can edit'),
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
