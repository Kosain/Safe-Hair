import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/app_colors.dart';
import '../../../platform/profile_file_upload.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/doctor_registration_provider.dart';
import '../../../services/firebase_service.dart';
import '../../../utils/doc_image_compress.dart';
import '../consultant_registration_ui.dart';
import '../doctor_registration_constants.dart';

/// Screen 1 — profile photo upload.
///
/// Upload logic: [_pickAndUpload] → [writeProfileImageTempFile] / [uploadDoctorProfileViaLocalFile]
/// (`lib/platform/profile_file_upload_io.dart`) and [FirebaseService.uploadBytes] (`lib/services/firebase_service.dart`).
/// Storage path: [doctorOnboardingProfileStoragePath] in `doctor_registration_constants.dart`.
class DrConsultantStep1Profile extends StatefulWidget {
  const DrConsultantStep1Profile({super.key});

  @override
  State<DrConsultantStep1Profile> createState() => _DrConsultantStep1ProfileState();
}

class _DrConsultantStep1ProfileState extends State<DrConsultantStep1Profile> {
  static const int _maxAttempts = 3;
  static const int _maxFallbackB64Bytes = 400000;

  String _messageForProfileError(String? technical) {
    final s = (technical ?? '').toLowerCase();
    if (s.contains('permission-denied') || s.contains('unauthorized')) {
      return 'Permission denied. Please sign in and try again.';
    }
    if (s.contains('quota-exceeded')) return 'Storage quota exceeded. Try again later.';
    if (s.contains('object-not-found')) return 'Upload completed but file link was unavailable. Please try again.';
    if (s.contains('network') || s.contains('connection')) return 'Network error while uploading. Please try again.';
    if (s.contains('timeout')) return 'Upload timed out. Please try again.';
    return 'Failed to upload photo. Please try again.';
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final auth = context.read<AuthProvider>();
    final p = context.read<DoctorRegistrationProvider>();
    final uid = auth.userId;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You must be signed in to upload a photo.')));
      }
      return;
    }

    final img = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 88);
    if (img == null || !mounted) return;

    final bytes = await img.readAsBytes();
    if (!mounted) return;

    final rawListed = Uint8List.fromList(bytes);
    if (!FirebaseService.isDoctorProfileImageAllowedFormat(rawListed)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please use a JPEG or PNG photo.')),
        );
      }
      return;
    }
    final typed = compressDoctorProfileForStorage(rawListed);
    if (typed.length > FirebaseService.kMaxDoctorProfileImageBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo must be 5 MB or smaller. Choose a smaller image.')),
        );
      }
      return;
    }
    final t = FirebaseService.doctorProfileImageType(typed);

    p.profilePictureUrl = null;
    p.profileImageBase64 = null;
    p.profileImagePreviewBytes = typed;
    p.fieldErrors.remove('profile');
    p.profileImageUploading = true;
    p.refresh();

    await FirebaseService.refreshAuthTokenForUpload();

    String? url;
    String? lastTechnical;

    for (var attempt = 0; attempt < _maxAttempts && (url == null || !url.startsWith('http')); attempt++) {
      final objectPath = doctorOnboardingProfileStoragePath(uid);
      String? tempPath;
      try {
        if (!kIsWeb) {
          tempPath = await writeProfileImageTempFile(typed, t.ext);
          if (tempPath != null) {
            final put = await uploadDoctorProfileViaLocalFile(
              storageChildPath: objectPath,
              localPath: tempPath,
              contentType: t.contentType,
            ).timeout(
              const Duration(seconds: 90),
              onTimeout: () => (url: null, err: 'timeout'),
            );
            if (put.url != null && put.url!.startsWith('http')) {
              url = put.url;
              lastTechnical = null;
              break;
            }
            lastTechnical = put.err ?? FirebaseService.lastStorageUploadError;
          }
        }

        if (url == null || !url.startsWith('http')) {
          FirebaseService.lastStorageUploadError = null;
          url = await FirebaseService.uploadBytes(
            objectPath,
            typed,
            contentType: t.contentType,
            uploadTimeout: const Duration(seconds: 90),
          ).timeout(
            const Duration(seconds: 100),
            onTimeout: () {
              FirebaseService.lastStorageUploadError ??= 'timeout';
              return null;
            },
          );
          if (url != null && url.startsWith('http')) {
            lastTechnical = null;
            break;
          }
          lastTechnical = FirebaseService.lastStorageUploadError ?? lastTechnical;
        }
      } finally {
        await deleteProfileTempFileIfExists(tempPath);
      }
    }

    if (!mounted) return;

    p.profileImageUploading = false;

    if (url == null || !url.startsWith('http')) {
      // Firebase Storage is paid/disabled on some projects; fallback to Firestore base64 like patient flow.
      if (typed.length <= _maxFallbackB64Bytes) {
        p.profilePictureUrl = null;
        p.profileImageBase64 = base64Encode(typed);
        p.profileImagePreviewBytes = typed;
        p.fieldErrors.remove('profile');
        p.refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo saved. Continue to the next step.')),
          );
        }
        return;
      }

      p.profilePictureUrl = null;
      p.profileImageBase64 = null;
      p.profileImagePreviewBytes = null;
      p.refresh();
      if (mounted) {
        final detail = lastTechnical ?? FirebaseService.lastStorageUploadError;
        debugPrint('=== PROFILE PHOTO UPLOAD ERROR ===');
        debugPrint('$detail');
        debugPrint('Doctor profile photo upload failed (project=${FirebaseService.debugProjectIdForLogs}): $detail');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _messageForProfileError(detail),
            ),
          ),
        );
      }
      return;
    }

    p.profilePictureUrl = url;
    p.profileImageBase64 = null;
    p.profileImagePreviewBytes = typed;
    p.fieldErrors.remove('profile');
    p.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DoctorRegistrationProvider>(
      builder: (context, p, _) {
        final uploading = p.profileImageUploading;
        final hasPreview = p.profileImagePreviewBytes != null && p.profileImagePreviewBytes!.isNotEmpty;
        final pickStyle = consultantPhotoPickButtonStyle();

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: consultantCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Upload your profile',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'A clear face photo helps patients recognize you.',
                  style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.textGrey.withValues(alpha: 0.92)),
                ),
                const SizedBox(height: 28),
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        radius: 76,
                        backgroundColor: const Color(0xFFF0F2F5),
                        backgroundImage: hasPreview ? MemoryImage(p.profileImagePreviewBytes!) : null,
                        child: !hasPreview
                            ? Icon(Icons.person_rounded, size: 72, color: AppColors.textGrey.withValues(alpha: 0.45))
                            : null,
                      ),
                      if (uploading)
                        Container(
                          width: 152,
                          height: 152,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.35),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 36,
                              height: 36,
                              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (p.fieldErrors['profile'] != null) ...[
                  const SizedBox(height: 14),
                  Text(p.fieldErrors['profile']!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ],
                if (p.hasProfilePictureReady && !uploading) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'Photo saved — tap Continue below.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: uploading ? null : () => _pickAndUpload(ImageSource.camera),
                        style: pickStyle,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.photo_camera_outlined, color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Camera',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: uploading ? null : () => _pickAndUpload(ImageSource.gallery),
                        style: pickStyle,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.photo_library_outlined, color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Upload/Gallery',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
