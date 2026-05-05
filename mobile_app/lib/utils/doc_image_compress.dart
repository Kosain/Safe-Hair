import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Shrinks certificate photos so Firestore document size stays under ~1 MiB when using base64 fallback.
Uint8List compressDocImageForFirestore(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;

  var im = decoded;
  const maxSide = 1100;
  if (im.width > maxSide || im.height > maxSide) {
    im = im.width >= im.height ? img.copyResize(im, width: maxSide) : img.copyResize(im, height: maxSide);
  }

  var encoded = Uint8List.fromList(img.encodeJpg(im, quality: 78));
  if (encoded.length > 450 * 1024) {
    im = im.width >= im.height ? img.copyResize(im, width: 800) : img.copyResize(im, height: 800);
    encoded = Uint8List.fromList(img.encodeJpg(im, quality: 68));
  }
  return encoded;
}

/// Resizes and re-encodes as JPEG for Firebase Storage profile uploads (stable decoder output).
Uint8List compressDoctorProfileForStorage(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;

  var im = decoded;
  const maxSide = 1600;
  if (im.width > maxSide || im.height > maxSide) {
    im = im.width >= im.height ? img.copyResize(im, width: maxSide) : img.copyResize(im, height: maxSide);
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 86));
}
