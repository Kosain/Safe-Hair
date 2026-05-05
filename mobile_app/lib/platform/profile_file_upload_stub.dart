import 'dart:typed_data';

/// Web / wasm: no `dart:io`; caller should use [FirebaseService.uploadBytes].
Future<({String? url, String? err})> uploadDoctorProfileViaLocalFile({
  required String storageChildPath,
  required String localPath,
  String? contentType,
}) async {
  return (url: null, err: null);
}

Future<String?> writeProfileImageTempFile(Uint8List bytes, String ext) async => null;

Future<void> deleteProfileTempFileIfExists(String? path) async {}
