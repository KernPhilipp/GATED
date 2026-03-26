import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

import '../auth/allowlist.dart';
import '../auth/hashing.dart';
import '../auth/jwt_service.dart';
import '../auth/request_auth.dart';
import '../db/database.dart';

Router buildAuthRouter(DatabaseService db) => Router()
  ..post('/auth/register', (Request request) async {
    final data = await _readJsonObject(request);
    if (data == null) {
      return Response.badRequest(body: 'Invalid JSON body');
    }

    final email = data['email'];
    final password = data['password'];
    if (email is! String ||
        password is! String ||
        email.trim().isEmpty ||
        password.isEmpty) {
      return Response.badRequest(body: 'Missing data');
    }

    final normalizedEmail = normalizeEmail(email);

    if (!isEmailAllowed(normalizedEmail)) {
      return Response.forbidden('Email not allowed');
    }

    final hash = await hashPassword(password);

    try {
      await db.createUser(
        email: normalizedEmail,
        passwordHash: hash.hashBase64,
        salt: hash.saltBase64,
      );
    } on SqliteException catch (e) {
      if (e.extendedResultCode == 2067) {
        return Response(409, body: 'User already exists');
      }
      return Response.internalServerError(body: 'Database error');
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
    return Response.ok('Registered');
  })
  ..post('/auth/login', (Request request) async {
    final data = await _readJsonObject(request);
    if (data == null) {
      return Response.badRequest(body: 'Invalid JSON body');
    }

    final email = data['email'];
    final password = data['password'];
    if (email is! String ||
        password is! String ||
        email.trim().isEmpty ||
        password.isEmpty) {
      return Response.badRequest(body: 'Missing data');
    }

    final normalizedEmail = normalizeEmail(email);
    final user = await db.getUserByEmail(normalizedEmail);
    if (user == null) {
      return Response.forbidden('Invalid credentials');
    }

    final valid = await verifyPassword(password, user.passwordHash, user.salt);

    if (!valid) {
      return Response.forbidden('Invalid credentials');
    }

    final token = generateJwt(userId: user.id, email: user.email);

    return Response.ok(
      jsonEncode({'token': token}),
      headers: {'Content-Type': 'application/json'},
    );
  })
  ..get('/auth/me', (Request request) async {
    try {
      final authContext = await authenticateRequest(request, db);
      return Response.ok(
        jsonEncode({
          'uid': authContext.user.id,
          'email': authContext.user.email,
          'createdAt': authContext.user.createdAt,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } on RequestAuthenticationException catch (e) {
      return e.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..post('/auth/change-password', (Request request) async {
    try {
      final authContext = await authenticateRequest(request, db);
      final data = await _readJsonObject(request);
      if (data == null) {
        return Response.badRequest(body: 'Invalid JSON body');
      }

      final currentPassword = data['currentPassword'];
      final newPassword = data['newPassword'];

      if (currentPassword is! String ||
          newPassword is! String ||
          currentPassword.isEmpty ||
          newPassword.isEmpty) {
        return Response.badRequest(body: 'Missing data');
      }

      if (currentPassword == newPassword) {
        return Response(409, body: 'Password unchanged');
      }

      final valid = await verifyPassword(
        currentPassword,
        authContext.user.passwordHash,
        authContext.user.salt,
      );

      if (!valid) {
        return Response.forbidden('Invalid current password');
      }

      final hash = await hashPassword(newPassword);
      await db.updateUserPassword(
        userId: authContext.user.id,
        passwordHash: hash.hashBase64,
        salt: hash.saltBase64,
      );

      return Response.ok('Password updated');
    } on RequestAuthenticationException catch (e) {
      return e.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  });

Future<Map<String, dynamic>?> _readJsonObject(Request request) async {
  final raw = await request.readAsString();
  if (raw.trim().isEmpty) {
    return null;
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  } catch (_) {
    return null;
  }

  return null;
}
