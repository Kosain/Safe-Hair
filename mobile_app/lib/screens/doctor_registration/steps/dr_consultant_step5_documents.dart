import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/doctor_registration_provider.dart';
import '../consultant_registration_ui.dart';
import '../doctor_registration_constants.dart';

String? _mimeFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  return null;
}

class DrConsultantStep5Documents extends StatefulWidget {
  const DrConsultantStep5Documents({super.key});

  @override
  State<DrConsultantStep5Documents> createState() => _DrConsultantStep5DocumentsState();
}

class _DrConsultantStep5DocumentsState extends State<DrConsultantStep5Documents> {
  String? _busyKey;
  static const int _maxDocFallbackBytes = 700 * 1024;

  String _uploadLabel(String? url, String? b64) {
    if ((url == null || url.trim().isEmpty) && (b64 == null || b64.trim().isEmpty)) return 'Not uploaded';
    if (url == null || url.trim().isEmpty) return 'Uploaded ✓  •  saved in profile';
    final parsed = Uri.tryParse(url);
    final object = parsed?.pathSegments.contains('o') == true
        ? Uri.decodeComponent(parsed!.pathSegments[parsed.pathSegments.indexOf('o') + 1])
        : null;
    final fileName = object == null || object.isEmpty ? null : object.split('/').last;
    return fileName == null || fileName.isEmpty ? 'Uploaded ✓' : 'Uploaded ✓  •  $fileName';
  }

  String _messageForUploadError(String? code, String? message) {
    final c = (code ?? '').toLowerCase();
    final m = (message ?? '').toLowerCase();
    if (c == 'permission-denied' || c == 'unauthorized') {
      return 'Permission denied. Please sign in and try again.';
    }
    if (c == 'object-not-found' || m.contains('object-not-found')) {
      return 'Upload completed but file link was unavailable. Please try again.';
    }
    if (c == 'network-request-failed' || m.contains('network')) {
      return 'Network error while uploading. Please try again.';
    }
    if (c == 'canceled') return 'Upload canceled.';
    if (c == 'quota-exceeded') return 'Storage quota exceeded. Try again later.';
    return 'Failed to upload document. Please try again.';
  }

  Future<String?> _downloadUrlWithRetry(Reference ref) async {
    for (var i = 0; i < 8; i++) {
      try {
        return await ref.getDownloadURL().timeout(const Duration(seconds: 20));
      } on FirebaseException catch (e) {
        if (e.code == 'object-not-found' && i < 7) {
          await Future<void>.delayed(Duration(milliseconds: 150 * (i + 1)));
          continue;
        }
        rethrow;
      }
    }
    return null;
  }

  Future<void> _uploadDocument(
    DoctorRegistrationProvider p,
    String uid,
    String key,
    String storageName,
    String ext,
    String? localPath,
    Uint8List bytes,
    void Function(String? url, String? b64) assign,
  ) async {
    setState(() => _busyKey = key);
    final safeExt = ext.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').replaceAll('jpeg', 'jpg');
    final useExt = safeExt.isEmpty ? 'jpg' : safeExt;
    final objectPath =
        '${consultantRegistrationStoragePrefix(uid)}/${storageName}_${DateTime.now().millisecondsSinceEpoch}.$useExt';
    final ref = FirebaseStorage.instance.ref().child(objectPath);
    String? url;
    String? code;
    String? message;
    try {
      debugPrint('=== DOCTOR DOCUMENT UPLOAD START ===');
      debugPrint('uid=$uid type=$storageName path=$objectPath');
      UploadTask task;
      final fp = (localPath ?? '').trim();
      if (fp.isNotEmpty) {
        final f = File(fp);
        if (await f.exists()) {
          task = ref.putFile(f, SettableMetadata(contentType: _mimeFromName('x.$useExt')));
        } else {
          task = ref.putData(bytes, SettableMetadata(contentType: _mimeFromName('x.$useExt')));
        }
      } else {
        task = ref.putData(bytes, SettableMetadata(contentType: _mimeFromName('x.$useExt')));
      }

      final snap = await task.timeout(const Duration(seconds: 120));
      if (snap.state != TaskState.success) {
        code = 'upload-not-success';
        message = 'state=${snap.state}';
      } else {
        url = await _downloadUrlWithRetry(ref);
        if (url == null) {
          code = 'object-not-found';
          message = 'No object exists at the desired reference.';
        } else {
          debugPrint('Upload successful: $url');
        }
      }
    } on FirebaseException catch (e, st) {
      code = e.code;
      message = e.message;
      debugPrint('=== UPLOAD ERROR ===');
      debugPrint('Firebase Storage Error: ${e.code} - ${e.message}');
      debugPrint('Doctor doc upload FirebaseError path=$objectPath code=${e.code} message=${e.message}\n$st');
    } on TimeoutException catch (e, st) {
      code = 'timeout';
      message = e.toString();
      debugPrint('Doctor doc upload timeout path=$objectPath error=$e\n$st');
    } catch (e, st) {
      code = 'unknown';
      message = e.toString();
      debugPrint('Doctor doc upload unknown path=$objectPath error=$e\n$st');
    }

    if (!mounted) return;
    setState(() => _busyKey = null);
    if (url == null) {
      // Fallback for no-Storage / Spark projects: keep compact base64 in Firestore payload.
      if (bytes.length <= _maxDocFallbackBytes) {
        assign(null, base64Encode(bytes));
        p.refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uploaded successfully (saved in profile).')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForUploadError(code, message))),
      );
      return;
    }
    assign(url, null);
    p.refresh();
  }

  Future<void> _pickImageOrFile(
    DoctorRegistrationProvider p,
    String uid,
    String key,
    String storageName,
    void Function(String? url, String? b64) assign,
  ) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, 'cam'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, 'gal'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('Choose file (PDF / image)'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'file') {
      final r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );
      if (r == null || r.files.isEmpty || r.files.single.bytes == null) return;
      final f = r.files.single;
      final ext = (f.extension ?? 'pdf').toLowerCase();
      await _uploadDocument(
        p,
        uid,
        key,
        storageName,
        ext,
        f.path,
        Uint8List.fromList(f.bytes!),
        assign,
      );
      return;
    }

    final src = choice == 'cam' ? ImageSource.camera : ImageSource.gallery;
    final x = await ImagePicker().pickImage(source: src, maxWidth: 2200, imageQuality: 88);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    final ext = x.name.contains('.') ? x.name.split('.').last.toLowerCase() : 'jpg';
    await _uploadDocument(
      p,
      uid,
      key,
      storageName,
      ext,
      x.path,
      Uint8List.fromList(bytes),
      assign,
    );
  }

  @override
  Widget build(BuildContext screenContext) {
    final uid = screenContext.watch<AuthProvider>().userId;
    final messenger = ScaffoldMessenger.of(screenContext);
    return Consumer<DoctorRegistrationProvider>(
      builder: (context, p, _) {
        if (uid == null) {
          return const Center(child: Text('Not signed in.'));
        }
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
                  'Documents & certifications',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textDark, letterSpacing: -0.3),
                ),
                const SizedBox(height: 8),
                Text(
                  'Upload your medical license and qualification certificate. PDF or images are accepted.',
                  style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.textGrey.withValues(alpha: 0.92)),
                ),
                const SizedBox(height: 22),
                _UploadTile(
                  title: 'Medical license (required)',
                  subtitle: _uploadLabel(p.medicalLicenseUrl, p.medicalLicenseBase64),
                  busy: _busyKey == 'lic',
                  onUpload: () => _pickImageOrFile(
                    p,
                    uid,
                    'lic',
                    'medical_license',
                    (u, b64) {
                      p.medicalLicenseUrl = u;
                      p.medicalLicenseBase64 = b64;
                    },
                  ),
                ),
                if (p.fieldErrors['license'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Text(p.fieldErrors['license']!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                const SizedBox(height: 12),
                _UploadTile(
                  title: 'Qualification certificate (required)',
                  subtitle: _uploadLabel(p.qualificationCertificateUrl, p.qualificationCertificateBase64),
                  busy: _busyKey == 'qual',
                  onUpload: () => _pickImageOrFile(
                    p,
                    uid,
                    'qual',
                    'qualification_cert',
                    (u, b64) {
                      p.qualificationCertificateUrl = u;
                      p.qualificationCertificateBase64 = b64;
                    },
                  ),
                ),
                if (p.fieldErrors['qualCert'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Text(p.fieldErrors['qualCert']!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Additional documents (optional, up to 2)',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black),
                ),
                const SizedBox(height: 8),
                if (p.additionalDocumentUrls.isNotEmpty)
                  ...List.generate(p.additionalDocumentUrls.length, (i) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.attach_file, size: 22),
                      title: Text(
                        'Document ${i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          p.additionalDocumentUrls.removeAt(i);
                          p.refresh();
                        },
                      ),
                    );
                  }),
                if (p.additionalDocumentUrls.length < 2)
                  OutlinedButton.icon(
                    onPressed: _busyKey != null
                        ? null
                        : () async {
                            final r = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
                              withData: true,
                            );
                            if (r == null || r.files.isEmpty || r.files.single.bytes == null) return;
                            final f = r.files.single;
                            setState(() => _busyKey = 'add');
                            final ext = (f.extension ?? 'pdf').toLowerCase();
                            final idx = p.additionalDocumentUrls.length;
                            final safeExt = ext.replaceAll(RegExp(r'[^a-z0-9]'), '').replaceAll('jpeg', 'jpg');
                            final useExt = safeExt.isEmpty ? 'pdf' : safeExt;
                            final path =
                                '${consultantRegistrationStoragePrefix(uid)}/extra_${idx}_${DateTime.now().millisecondsSinceEpoch}.$useExt';
                            final ref = FirebaseStorage.instance.ref().child(path);
                            String? url;
                            try {
                              final task = ref.putData(
                                Uint8List.fromList(f.bytes!),
                                SettableMetadata(contentType: _mimeFromName(f.name)),
                              );
                              final snap = await task.timeout(const Duration(seconds: 120));
                              if (snap.state == TaskState.success) {
                                url = await ref.getDownloadURL().timeout(const Duration(seconds: 25));
                              } else {
                                debugPrint('Doctor additional doc upload state fail path=$path state=${snap.state}');
                              }
                            } on FirebaseException catch (e, st) {
                              debugPrint('Doctor additional doc FirebaseError path=$path code=${e.code} message=${e.message}\n$st');
                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(content: Text(_messageForUploadError(e.code, e.message))),
                                );
                              }
                            } on TimeoutException catch (e) {
                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(content: Text(_messageForUploadError('timeout', '$e'))),
                                );
                              }
                            } catch (e, st) {
                              debugPrint('Doctor additional doc unknown path=$path error=$e\n$st');
                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(content: Text(_messageForUploadError('unknown', '$e'))),
                                );
                              }
                            }
                            if (!mounted) return;
                            setState(() => _busyKey = null);
                            if (url != null) {
                              p.additionalDocumentUrls.add(url);
                              p.additionalDocumentBase64.add('');
                              p.refresh();
                            } else if (f.bytes!.length <= _maxDocFallbackBytes) {
                              p.additionalDocumentUrls.add('');
                              p.additionalDocumentBase64.add(base64Encode(f.bytes!));
                              p.refresh();
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Additional document saved in profile.')),
                              );
                            }
                          },
                    icon: const Icon(Icons.add),
                    label: const Text('Add document'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textDark,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onUpload,
  });

  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_upload_outlined, color: AppColors.textGrey.withValues(alpha: 0.85)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.black)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12.5, color: AppColors.textGrey.withValues(alpha: 0.95))),
              ],
            ),
          ),
          FilledButton(
            onPressed: busy ? null : onUpload,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Upload'),
          ),
        ],
      ),
    );
  }
}
