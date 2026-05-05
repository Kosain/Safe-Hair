import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/doctor_registration/doctor_registration_constants.dart';

class ConsultantDaySchedule {
  ConsultantDaySchedule({
    this.available = false,
    this.start,
    this.end,
  });

  bool available;
  TimeOfDay? start;
  TimeOfDay? end;

  Map<String, dynamic> toFirestore() {
    if (!available) {
      return {'available': false};
    }
    String tf(TimeOfDay? t) {
      if (t == null) return '';
      final h = t.hour.toString().padLeft(2, '0');
      final m = t.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }

    return {
      'available': true,
      'start': tf(start),
      'end': tf(end),
    };
  }
}

/// Single-doctor profile registration (6 steps). Uses Firebase Auth uid as `doctors/{uid}`.
class DoctorRegistrationProvider extends ChangeNotifier {
  static const int totalSteps = 6;

  int currentStep = 0;
  bool submitting = false;

  // Step 1 — profile (URL from Storage after upload; bytes kept for avatar until reset)
  String? profilePictureUrl;
  String? profileImageBase64;
  Uint8List? profileImagePreviewBytes;
  bool profileImageUploading = false;

  bool get hasProfilePictureReady =>
      (profilePictureUrl != null && profilePictureUrl!.trim().isNotEmpty && profilePictureUrl!.trim().startsWith('http')) ||
      (profileImageBase64 != null && profileImageBase64!.trim().isNotEmpty);

  // Step 2 — personal
  String fullName = '';
  DateTime? dob;
  String phone = '';
  String cnic = '';
  String address = '';

  // Step 3 — expertise
  String qualification = '';
  String specialization = '';
  String specializationOther = '';
  String registrationNumber = '';
  int yearsExperience = 0;

  // Step 4 — clinic (practice location only; single consultant)
  String clinicName = '';
  String clinicAddress = '';
  String city = '';
  int consultationFee = 0;

  // Step 5 — documents
  String? medicalLicenseUrl;
  String? medicalLicenseBase64;
  String? qualificationCertificateUrl;
  String? qualificationCertificateBase64;
  final List<String> additionalDocumentUrls = [];
  final List<String> additionalDocumentBase64 = [];

  // Step 6 — availability
  final Map<String, ConsultantDaySchedule> daySchedules = {
    for (final d in kConsultantWeekdays) d: ConsultantDaySchedule(),
  };
  final Set<String> selectedPresetSlots = {};
  int? remindMeBeforeMinutes;

  final Map<String, String> fieldErrors = {};

  void refresh() => notifyListeners();

  void clearFieldErrors() {
    fieldErrors.clear();
  }

  void setFieldError(String key, String message) {
    fieldErrors[key] = message;
  }

  /// Reset all fields (after successful finish or when abandoning flow).
  void reset({bool notify = true}) {
    currentStep = 0;
    submitting = false;
    profilePictureUrl = null;
    profileImageBase64 = null;
    profileImagePreviewBytes = null;
    profileImageUploading = false;
    fullName = '';
    dob = null;
    phone = '';
    cnic = '';
    address = '';
    qualification = '';
    specialization = '';
    specializationOther = '';
    registrationNumber = '';
    yearsExperience = 0;
    clinicName = '';
    clinicAddress = '';
    city = '';
    consultationFee = 0;
    medicalLicenseUrl = null;
    medicalLicenseBase64 = null;
    qualificationCertificateUrl = null;
    qualificationCertificateBase64 = null;
    additionalDocumentUrls.clear();
    additionalDocumentBase64.clear();
    for (final d in kConsultantWeekdays) {
      daySchedules[d] = ConsultantDaySchedule();
    }
    selectedPresetSlots.clear();
    remindMeBeforeMinutes = null;
    fieldErrors.clear();
    if (notify) notifyListeners();
  }

  void previousStep() {
    if (currentStep > 0) {
      currentStep--;
      notifyListeners();
    }
  }

  static bool isValidCnic(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'\s'), '');
    if (RegExp(r'^\d{5}-\d{7}$').hasMatch(s)) return true;
    final digits = s.replaceAll(RegExp(r'\D'), '');
    return digits.length == 13;
  }

  String? normalizeCnic(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 13) return null;
    return '${digits.substring(0, 5)}-${digits.substring(5)}';
  }

  int _minutes(TimeOfDay? t) {
    if (t == null) return -1;
    return t.hour * 60 + t.minute;
  }

  String? validateStep(int step) {
    clearFieldErrors();
    switch (step) {
      case 0:
        if (profileImageUploading || !hasProfilePictureReady) {
          setFieldError(
            'profile',
            profileImageUploading
                ? 'Please wait for your photo to finish uploading.'
                : 'Please take or upload a profile photo.',
          );
          return fieldErrors['profile'];
        }
        break;
      case 1:
        if (fullName.trim().isEmpty) {
          setFieldError('fullName', 'Full name is required.');
          return fieldErrors['fullName'];
        }
        if (dob == null) {
          setFieldError('dob', 'Date of birth is required.');
          return fieldErrors['dob'];
        }
        final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
        if (phoneDigits.length < 10) {
          setFieldError('phone', 'Enter a valid phone number with country code.');
          return fieldErrors['phone'];
        }
        if (!isValidCnic(cnic)) {
          setFieldError('cnic', 'Enter a valid CNIC (#####-####### or 13 digits).');
          return fieldErrors['cnic'];
        }
        if (address.trim().isEmpty) {
          setFieldError('address', 'Address is required.');
          return fieldErrors['address'];
        }
        break;
      case 2:
        if (qualification.trim().isEmpty) {
          setFieldError('qualification', 'Qualification is required.');
          return fieldErrors['qualification'];
        }
        if (specialization.trim().isEmpty) {
          setFieldError('specialization', 'Select a specialization.');
          return fieldErrors['specialization'];
        }
        if (specialization == 'Other' && specializationOther.trim().isEmpty) {
          setFieldError('specializationOther', 'Please specify your specialization.');
          return fieldErrors['specializationOther'];
        }
        if (registrationNumber.trim().isEmpty) {
          setFieldError('registrationNumber', 'Registration / license number is required.');
          return fieldErrors['registrationNumber'];
        }
        if (yearsExperience < 0) {
          setFieldError('yearsExperience', 'Years of experience cannot be negative.');
          return fieldErrors['yearsExperience'];
        }
        break;
      case 3:
        if (clinicName.trim().isEmpty) {
          setFieldError('clinicName', 'Clinic or hospital name is required.');
          return fieldErrors['clinicName'];
        }
        if (clinicAddress.trim().isEmpty) {
          setFieldError('clinicAddress', 'Clinic address is required.');
          return fieldErrors['clinicAddress'];
        }
        if (city.trim().isEmpty) {
          setFieldError('city', 'City is required.');
          return fieldErrors['city'];
        }
        if (consultationFee < 0) {
          setFieldError('consultationFee', 'Consultation fee cannot be negative.');
          return fieldErrors['consultationFee'];
        }
        break;
      case 4:
        final hasLicense = (medicalLicenseUrl != null && medicalLicenseUrl!.trim().isNotEmpty) ||
            (medicalLicenseBase64 != null && medicalLicenseBase64!.trim().isNotEmpty);
        if (!hasLicense) {
          setFieldError('license', 'Medical license upload is required.');
          return fieldErrors['license'];
        }
        final hasQual = (qualificationCertificateUrl != null && qualificationCertificateUrl!.trim().isNotEmpty) ||
            (qualificationCertificateBase64 != null && qualificationCertificateBase64!.trim().isNotEmpty);
        if (!hasQual) {
          setFieldError('qualCert', 'Qualification certificate is required.');
          return fieldErrors['qualCert'];
        }
        break;
      case 5:
        for (final day in kConsultantWeekdays) {
          final slot = daySchedules[day]!;
          if (!slot.available) continue;
          if (slot.start == null || slot.end == null) {
            setFieldError(day, 'Set start and end for ${weekdayTitle(day)}.');
            return fieldErrors[day];
          }
          final sm = _minutes(slot.start);
          final em = _minutes(slot.end);
          if (em <= sm) {
            setFieldError(day, 'End time must be after start (${weekdayTitle(day)}).');
            return fieldErrors[day];
          }
        }
        break;
    }
    return null;
  }

  bool tryAdvanceStep() {
    final err = validateStep(currentStep);
    if (err != null) {
      notifyListeners();
      return false;
    }
    fieldErrors.clear();
    if (currentStep < totalSteps - 1) {
      currentStep++;
      notifyListeners();
    }
    return true;
  }

  String specializationForFirestore() {
    if (specialization == 'Other') {
      return specializationOther.trim().isEmpty ? 'Other' : specializationOther.trim();
    }
    return specialization.trim();
  }

  Map<String, dynamic> buildFirestorePayload(String uid, String email) {
    final availability = <String, dynamic>{};
    for (final day in kConsultantWeekdays) {
      availability[day] = daySchedules[day]!.toFirestore();
    }

    return {
      'userId': uid,
      'role': 'doctor',
      'email': email,
      'fullName': fullName.trim(),
      'dob': dob == null ? null : Timestamp.fromDate(dob!),
      'phone': phone.trim(),
      'cnic': normalizeCnic(cnic) ?? cnic.trim(),
      'address': address.trim(),
      'qualification': qualification.trim(),
      'specialization': specializationForFirestore(),
      'licenseNumber': registrationNumber.trim(),
      'registrationNumber': registrationNumber.trim(),
      'yearsExperience': yearsExperience,
      'clinicName': clinicName.trim(),
      'clinicAddress': clinicAddress.trim(),
      'city': city.trim(),
      'consultationFee': consultationFee,
      'profilePictureUrl': profilePictureUrl,
      'profileImageBase64': profileImageBase64,
      'medicalLicenseUrl': medicalLicenseUrl,
      'medicalLicenseBase64': medicalLicenseBase64,
      'qualificationCertificateUrl': qualificationCertificateUrl,
      'qualificationCertificateBase64': qualificationCertificateBase64,
      'additionalDocumentUrls': List<String>.from(additionalDocumentUrls),
      'additionalDocumentBase64': List<String>.from(additionalDocumentBase64),
      'availability': availability,
      'presetConsultationSlots': () {
        final slots = selectedPresetSlots.toList();
        slots.sort();
        return slots;
      }(),
      'remindMeBeforeMinutes': remindMeBeforeMinutes,
      'profileCompleted': true,
      'profileCompletedAt': DateTime.now().toIso8601String(),
      'isVerified': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
