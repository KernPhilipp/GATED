import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

const refreshTokenLifetime = Duration(days: 30);

final Random _random = Random.secure();

String generateSessionId() {
  return _encodeTokenBytes(_randomBytes(24));
}

String generateRefreshToken() {
  return _encodeTokenBytes(_randomBytes(32));
}

Future<String> hashRefreshToken(String refreshToken) async {
  final digest = await Sha256().hash(utf8.encode(refreshToken));
  return base64Encode(digest.bytes);
}

List<int> _randomBytes(int length) {
  return List<int>.generate(length, (_) => _random.nextInt(256));
}

String _encodeTokenBytes(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}
