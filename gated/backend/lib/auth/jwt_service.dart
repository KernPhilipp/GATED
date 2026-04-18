import 'dart:io';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dotenv/dotenv.dart';

final DotEnv _dotEnv = DotEnv();
String? _jwtSecret;
const accessTokenLifetime = Duration(minutes: 15);

void loadJwtEnv({String? overrideSecret}) {
  if (overrideSecret != null && overrideSecret.trim().isNotEmpty) {
    _jwtSecret = overrideSecret.trim();
    return;
  }

  final envFile = File('.env');
  if (!envFile.existsSync()) {
    throw StateError(
      'Missing .env file. Create it from .env.example before starting the backend.',
    );
  }

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

String generateAccessToken({
  required int userId,
  required String email,
  required String sessionId,
}) {
  final jwt = JWT({
    'uid': userId,
    'email': email,
    'sid': sessionId,
  }, issuer: 'gated_backend');

  return jwt.sign(
    SecretKey(_requireJwtSecret()),
    expiresIn: accessTokenLifetime,
  );
}

JWT verifyAccessToken(String token) {
  return JWT.verify(token, SecretKey(_requireJwtSecret()));
}

String _requireJwtSecret() {
  final jwtSecret = _jwtSecret;
  if (jwtSecret == null || jwtSecret.isEmpty) {
    throw StateError('JWT secret was not initialized.');
  }
  return jwtSecret;
}
