import 'dart:convert';

import 'package:cryptography/cryptography.dart';

const int defaultIterations = 100000;
const int defaultSaltBytes = 16;
const int defaultHashBytes = 32;

class PasswordHash {
  final String hashBase64;
  final String saltBase64;
  final int iterations;
  final int hashBytes;

  const PasswordHash({
    required this.hashBase64,
    required this.saltBase64,
    required this.iterations,
    required this.hashBytes,
  });
}

Future<PasswordHash> hashPassword(
  String password, {
  int iterations = defaultIterations,
  int saltBytes = defaultSaltBytes,
  int hashBytes = defaultHashBytes,
}) async {
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: hashBytes * 8,
  );

  final salt = SecretKeyData.random(length: saltBytes);
  final secretKey = SecretKey(utf8.encode(password));
  final derivedKey = await pbkdf2.deriveKey(
    secretKey: secretKey,
    nonce: salt.bytes,
  );

  final hashBytesList = await derivedKey.extractBytes();

  return PasswordHash(
    hashBase64: base64Encode(hashBytesList),
    saltBase64: base64Encode(salt.bytes),
    iterations: iterations,
    hashBytes: hashBytes,
  );
}

Future<bool> verifyPassword(
  String password,
  String expectedHashBase64,
  String saltBase64, {
  int iterations = defaultIterations,
  int hashBytes = defaultHashBytes,
}) async {
  final saltBytes = base64Decode(saltBase64);

  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: hashBytes * 8,
  );

  final derivedKey = await pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: saltBytes,
  );

  final candidateBytes = await derivedKey.extractBytes();
  final expectedBytes = base64Decode(expectedHashBase64);

  return _constantTimeEquals(candidateBytes, expectedBytes);
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
