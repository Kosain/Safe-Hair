import 'dart:typed_data';

import 'profile_file_upload_stub.dart' if (dart.library.io) 'profile_file_upload_io.dart' as impl;

/// On IO: [putFile] then [TaskSnapshot.ref.getDownloadURL]. On web: returns `(null,null)` — use bytes upload instead.
Future<({String? url, String? err})> uploadDoctorProfileViaLocalFile({
  required String storageChildPath,
  required String localPath,
  String? contentType,
}) {
  return impl.uploadDoctorProfileViaLocalFile(
    storageChildPath: storageChildPath,
    localPath: localPath,
    contentType: contentType,
  );
}

Future<String?> writeProfileImageTempFile(Uint8List bytes, String ext) =>
    impl.writeProfileImageTempFile(bytes, ext);

Future<void> deleteProfileTempFileIfExists(String? path) => impl.deleteProfileTempFileIfExists(path);
