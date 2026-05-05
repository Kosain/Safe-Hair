import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

FirebaseStorage _scopedStorage() {
  final raw = (Firebase.app().options.storageBucket ?? '').trim();
  if (raw.isEmpty) return FirebaseStorage.instance;
  final gs = raw.startsWith('gs://') ? raw : 'gs://$raw';
  return FirebaseStorage.instanceFor(app: Firebase.app(), bucket: gs);
}

String _newDownloadToken() {
  final r = Random();
  final a = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final b = r.nextInt(1 << 32).toRadixString(16);
  final c = r.nextInt(1 << 32).toRadixString(16);
  return '$a$b$c';
}

String? _bucketHostName() {
  final raw = (Firebase.app().options.storageBucket ?? '').trim();
  if (raw.isEmpty) return null;
  return raw.replaceFirst('gs://', '');
}

String? _manualDownloadUrl({
  required String bucket,
  required String fullPath,
  required String token,
}) {
  if (bucket.isEmpty || fullPath.isEmpty || token.isEmpty) return null;
  final encoded = Uri.encodeComponent(fullPath);
  return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$encoded?alt=media&token=$token';
}

/// Uploads using [Reference.putFile], then resolves URL from [TaskSnapshot.ref] (same reference as upload).
Future<({String? url, String? err})> uploadDoctorProfileViaLocalFile({
  required String storageChildPath,
  required String localPath,
  String? contentType,
}) async {
  try {
    final file = File(localPath);
    if (!await file.exists()) {
      return (url: null, err: 'Local file missing');
    }
    final ref = _scopedStorage().ref().child(storageChildPath);
    final token = _newDownloadToken();
    final meta = SettableMetadata(
      contentType: contentType,
      customMetadata: {'firebaseStorageDownloadTokens': token},
    );
    final task = ref.putFile(file, meta);
    await task.timeout(const Duration(seconds: 120));
    final snap = task.snapshot;
    if (snap.state != TaskState.success) {
      return (url: null, err: 'Upload did not complete (state: ${snap.state}).');
    }
    final urlRef = snap.ref;
    for (var i = 0; i < 10; i++) {
      try {
        final url = await urlRef.getDownloadURL().timeout(const Duration(seconds: 25));
        return (url: url, err: null);
      } on FirebaseException catch (e) {
        final detail = 'code=${e.code} message=${e.message ?? 'n/a'}';
        if (e.code == 'object-not-found' && i < 9) {
          await Future<void>.delayed(Duration(milliseconds: 150 * (i + 1)));
          continue;
        }
        if (e.code == 'object-not-found') {
          final bucket = _bucketHostName() ?? '';
          final fallback = _manualDownloadUrl(
            bucket: bucket,
            fullPath: urlRef.fullPath,
            token: token,
          );
          if (fallback != null) return (url: fallback, err: null);
        }
        return (url: null, err: detail);
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('object-not-found') && i < 9) {
          await Future<void>.delayed(Duration(milliseconds: 150 * (i + 1)));
          continue;
        }
        return (url: null, err: e.toString());
      }
    }
    return (url: null, err: 'Could not get download link after upload.');
  } on FirebaseException catch (e) {
    return (url: null, err: 'code=${e.code} message=${e.message ?? 'n/a'}');
  } on TimeoutException catch (e) {
    return (url: null, err: 'timeout: $e');
  } catch (e) {
    return (url: null, err: e.toString());
  }
}

/// Writes image bytes to app temp so [putFile] always uses a real filesystem path (fixes Android `content://`).
Future<String?> writeProfileImageTempFile(Uint8List bytes, String ext) async {
  try {
    final dir = await getTemporaryDirectory();
    final e = ext.toLowerCase();
    final useExt = (e == 'png' || e == 'jpg' || e == 'jpeg') ? (e == 'jpeg' ? 'jpg' : e) : 'jpg';
    final f = File('${dir.path}/safehair_profile_${DateTime.now().microsecondsSinceEpoch}.$useExt');
    await f.writeAsBytes(bytes, flush: true);
    return f.absolute.path;
  } catch (_) {
    return null;
  }
}

Future<void> deleteProfileTempFileIfExists(String? path) async {
  if (path == null || path.isEmpty) return;
  try {
    await File(path).delete();
  } catch (_) {}
}
