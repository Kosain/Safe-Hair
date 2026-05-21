import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import '../core/nav_helper.dart';
import '../core/responsive.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../widgets/animated_primary_button.dart';

class PatientDetailsScreen extends StatefulWidget {
  const PatientDetailsScreen({super.key});

  @override
  State<PatientDetailsScreen> createState() => _PatientDetailsScreenState();
}

class _PatientDetailsScreenState extends State<PatientDetailsScreen> {
  static const Color _fieldBg = Colors.white;
  int _step = 1;
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  dynamic _profileImage; // File on mobile/desktop, Uint8List on web
  Uint8List? _profileImageBytes;
  String? _profileImageUrl;

  String _name = '';
  int? _day, _month, _year;
  String? _gender;
  String _mobile = '';
  String _address = '';
  String? _primaryConcern;
  String? _duration;
  String? _familyHistory;
  String? _previousTreatments;
  String? _scalpCondition;
  String? _smokingStatus;
  String? _stressLevel;
  String? _dietType;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryGreen,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => _step > 1 ? setState(() => _step--) : backOrGo(context, '/dashboard'),
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textDark),
        ),
        title: Text('Patient Details', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              if (context.mounted) context.go('/role');
            },
            child: Text('Sign out', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: Responsive.maxContentWidth(context) ?? double.infinity),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _fieldBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text('Step $_step/4', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: _step / 4,
                      backgroundColor: AppColors.textGrey.withOpacity(0.2),
                      valueColor: const AlwaysStoppedAnimation(AppColors.darkButton),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_step == 1) _buildProfileUploadStep(),
            if (_step == 2) _buildBasicDetails(),
            if (_step == 3) _buildMedicalHistory(),
            if (_step == 4) _buildLifestyleInfo(),
            const SizedBox(height: 32),
            if (_step == 1)
              Row(
                children: [
                  Expanded(
                    child: AnimatedPrimaryButton(
                      borderRadius: 28,
                      height: 48,
                      gradientColors: const [AppColors.darkButton, AppColors.darkButton],
                      onPressed: _loading ? null : () => setState(() => _step = 2),
                      child: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedPrimaryButton(
                      borderRadius: 28,
                      height: 48,
                      gradientColors: const [AppColors.darkButton, AppColors.darkButton],
                      onPressed: _loading ? null : _handleContinue,
                      child: _loading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Continue'),
                    ),
                  ),
                ],
              )
            else
              Center(
                child: SizedBox(
                  width: 140,
                  child: AnimatedPrimaryButton(
                    borderRadius: 28,
                    height: 48,
                    gradientColors: const [AppColors.darkButton, AppColors.darkButton],
                    onPressed: _loading ? null : _handleContinue,
                    child: _loading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Continue'),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    ),
    );
  }

  Widget _buildProfileUploadStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _fieldBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Center(
            child: Text('Upload your profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          ),
          const SizedBox(height: 24),
          CircleAvatar(
            radius: 80,
            backgroundColor: AppColors.cardBackground,
            backgroundImage: _profileImage == null
                ? null
                : (kIsWeb ? MemoryImage(_profileImage as Uint8List) : FileImage(_profileImage as File) as ImageProvider),
            child: _profileImage == null ? const Icon(Icons.person, size: 92, color: AppColors.textGrey) : null,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 190,
            child: AnimatedPrimaryButton(
              borderRadius: 28,
              height: 48,
              gradientColors: const [AppColors.darkButton, AppColors.darkButton],
              onPressed: _loading ? null : () => _pickProfileImage(ImageSource.camera),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Take a photo'),
                  SizedBox(width: 8),
                  Icon(Icons.camera_alt, color: Colors.white, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 190,
            child: AnimatedPrimaryButton(
              borderRadius: 28,
              height: 48,
              gradientColors: const [AppColors.darkButton, AppColors.darkButton],
              onPressed: _loading ? null : () => _pickProfileImage(ImageSource.gallery),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Upload a photo'),
                  SizedBox(width: 8),
                  Icon(Icons.upload, color: Colors.white, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicDetails() {
    return Form(
      key: _formKey,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _fieldBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text('Basic Personal Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textDark)),
            ),
            const SizedBox(height: 16),
            Text('Patient\'s Name', style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textDark)),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _name,
              cursorColor: Colors.black,
              decoration: InputDecoration(
                filled: true,
                fillColor: _fieldBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF1F3F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF1F3F0))),
              ),
              onChanged: (v) => _name = v,
              validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 20),
            Text('Date of Birth', style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textDark)),
            const SizedBox(height: 8),
            Row(
              children: [
                Flexible(child: _buildDropdown('Day', _day, [for (int i = 1; i <= 31; i++) i], (v) => _day = v)),
                const SizedBox(width: 8),
                Flexible(child: _buildDropdown('Month', _month, [for (int i = 1; i <= 12; i++) i], (v) => _month = v)),
                const SizedBox(width: 8),
                Flexible(
                  child: _buildDropdown(
                    'Year',
                    _year,
                    [for (int i = DateTime.now().year; i >= 1940; i--) i],
                    (v) => _year = v,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Gender', style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textDark)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 0,
              children: ['Male', 'Female', 'Others'].map((g) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: 0.85,
                      child: Radio<String>(value: g, groupValue: _gender, onChanged: (v) => setState(() => _gender = v), activeColor: AppColors.darkButton),
                    ),
                    Text(g),
                  ],
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text('Mobile Number', style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textDark)),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _mobile,
              cursorColor: Colors.black,
              decoration: const InputDecoration(hintText: '+92 0000000000'),
              keyboardType: TextInputType.phone,
              onChanged: (v) => _mobile = v,
              validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 20),
            Text('Address', style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textDark)),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _address,
              cursorColor: Colors.black,
              decoration: const InputDecoration(hintText: 'House No#'),
              onChanged: (v) => _address = v,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown<T>(String hint, T? value, List<T> items, Function(T?) onChanged) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        filled: true,
        fillColor: _fieldBg,
      ),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e.toString(), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildMedicalHistory() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _fieldBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text('Medical & Hair History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          ),
          const SizedBox(height: 24),
          _buildRadioSection('Primary Concern', AppConstants.primaryConcerns, _primaryConcern, (v) => setState(() => _primaryConcern = v)),
          const SizedBox(height: 20),
          _buildRadioSection('Duration of Hair Problem', AppConstants.durationOptions, _duration, (v) => setState(() => _duration = v)),
          const SizedBox(height: 20),
          _buildRadioSection('Family History of Hair Loss', ['Yes', 'No'], _familyHistory, (v) => setState(() => _familyHistory = v)),
          const SizedBox(height: 20),
          _buildRadioSection('Previous Treatments Taken', AppConstants.previousTreatments, _previousTreatments, (v) => setState(() => _previousTreatments = v)),
          const SizedBox(height: 20),
          _buildRadioSection('Scalp Condition', AppConstants.scalpConditions, _scalpCondition, (v) => setState(() => _scalpCondition = v)),
        ],
      ),
    );
  }

  Widget _buildRadioSection(String title, List<String> options, String? value, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: options.map((o) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 0.82,
                  child: Radio<String>(value: o, groupValue: value, onChanged: onChanged, activeColor: AppColors.darkButton),
                ),
                Text(o, style: TextStyle(fontSize: 14, color: AppColors.textDark)),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildLifestyleInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _fieldBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text('Lifestyle Information', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          ),
          const SizedBox(height: 24),
          _buildRadioSection('Smoking Status', ['Yes', 'No'], _smokingStatus, (v) => setState(() => _smokingStatus = v)),
          const SizedBox(height: 20),
          _buildRadioSection('Stress Level', ['Low', 'Medium', 'High'], _stressLevel, (v) => setState(() => _stressLevel = v)),
          const SizedBox(height: 20),
          _buildRadioSection('Diet Type', ['Balanced', 'Vegetarian', 'Poor', 'Unknown'], _dietType, (v) => setState(() => _dietType = v)),
        ],
      ),
    );
  }

  Future<void> _pickProfileImage(ImageSource source) async {
    final xFile = await _picker.pickImage(source: source, maxWidth: 900);
    if (xFile == null) return;
    final bytes = await xFile.readAsBytes();
    setState(() {
      _profileImageBytes = bytes;
      _profileImage = kIsWeb ? bytes : File(xFile.path);
    });
    context.read<AuthProvider>().setUserPhoto(bytes: bytes);
  }

  Future<void> _handleContinue() async {
    if (_step == 2 && !_formKey.currentState!.validate()) return;
    if (_step < 4) {
      setState(() => _step++);
      return;
    }

    final authUid = FirebaseService.currentUser?.uid ?? context.read<AuthProvider>().userId;

    setState(() => _loading = true);

    try {
      if (authUid == null || authUid.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must be signed in to save your profile. Please log in again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (_profileImageBytes != null && FirebaseService.isInitialized) {
        try {
          _profileImageUrl = await FirebaseService.uploadImage(
            'patients/$authUid/profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
            _profileImageBytes!,
          ).timeout(const Duration(seconds: 20));
        } catch (_) {}
      }

      // Never embed photos as base64 in Firestore (1 MiB limit + rules noise); use Storage URL only.
      final data = {
        'userId': authUid,
        'user_id': authUid,
        'profileImageUrl': _profileImageUrl,
        'name': _name,
        // Keep both DOB and legacy age_* keys for backward compatibility.
        'dob_day': _day,
        'dob_month': _month,
        'dob_year': _year,
        'age_day': _day,
        'age_month': _month,
        'age_year': _year,
        'gender': _gender,
        'mobile': _mobile,
        'address': _address,
        'primary_concern': _primaryConcern,
        'duration': _duration,
        'family_history': _familyHistory,
        'previous_treatments': _previousTreatments,
        'scalp_condition': _scalpCondition,
        'smoking_status': _smokingStatus,
        'stress_level': _stressLevel,
        'diet_type': _dietType,
        'createdAt': DateTime.now().toIso8601String(),
      };

      if (!FirebaseService.isInitialized) {
        try {
          await ApiService().savePatientDetails(data).timeout(
            const Duration(seconds: 5),
            onTimeout: () => false,
          );
        } catch (_) {
          // Backend optional; continue to Firebase.
        }
      }

      if (FirebaseService.isInitialized) {
        String? saved;
        try {
          saved = await FirebaseService.savePatientDetails(data).timeout(const Duration(seconds: 25));
        } on TimeoutException {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Saving profile timed out. Check your connection and Firestore rules, then try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not save your profile. Please try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        if (saved == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                FirebaseService.lastPatientSaveError ??
                    'Could not save your profile (Firebase). Check internet and Firestore rules, then try again.',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      if (_name.trim().isNotEmpty) {
        context.read<AuthProvider>().setUserProfile(_name.trim());
      }
      if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
        context.read<AuthProvider>().setUserPhoto(url: _profileImageUrl);
      }

      if (!mounted) return;

      context.read<AuthProvider>().markPatientRegistered();
      context.go('/dashboard');

      final nameTrim = _name.trim();
      final photoUrl = _profileImageUrl;
      if (FirebaseService.isInitialized) {
        unawaited(
          (() async {
            try {
              if (nameTrim.isNotEmpty) {
                await FirebaseService.currentUser?.updateDisplayName(nameTrim);
              }
              if (photoUrl != null && photoUrl.isNotEmpty) {
                await FirebaseService.currentUser?.updatePhotoURL(photoUrl);
              }
            } catch (_) {}
          })(),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}
