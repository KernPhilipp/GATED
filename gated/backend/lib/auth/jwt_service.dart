import 'dart:io';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dotenv/dotenv.dart';

final DotEnv _dotEnv = DotEnv();
late final String _jwtSecret;

void loadJwtEnv() {
  _dotEnv.load();
  _jwtSecret = _loadJwtSecret();
}

String _loadJwtSecret() {
  final value = _dotEnv['JWT_SECRET'] ?? Platform.environment['JWT_SECRET'];
  if (value == null || value.trim().isEmpty) {
    throw StateError(
      'JWT_SECRET is not set. Please set JWT_SECRET in the environment.',
    );
  }
  return value.trim();
}

String generateJwt({required int userId, required String email}) {
  final jwt = JWT({'uid': userId, 'email': email}, issuer: 'gated_backend');

  return jwt.sign(SecretKey(_jwtSecret), expiresIn: const Duration(hours: 1));
}

JWT verifyJwt(String token) {
  return JWT.verify(token, SecretKey(_jwtSecret));
}
