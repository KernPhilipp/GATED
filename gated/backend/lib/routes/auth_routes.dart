import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

import '../auth/email_access_control.dart';
import '../auth/hashing.dart';
import '../auth/jwt_service.dart';
import '../auth/refresh_token_service.dart';
import '../auth/request_auth.dart';
import '../db/database.dart';
import 'admin_events.dart';

const _jsonHeaders = {'Content-Type': 'application/json'};

Router buildAuthRouter(
  DatabaseService db,
  EmailAccessControlService accessControlService, [
  AdminEventsBroker? adminEventsBroker,
]) => Router()
  ..post('/auth/register', (Request request) async {
    await accessControlService.sync();
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

    final role = await accessControlService.roleForEmail(normalizedEmail);
    if (role == null) {
      return Response.forbidden('Email not allowed');
    }

    final hash = await hashPassword(password);

    try {
      await db.createUser(
        email: normalizedEmail,
        role: role,
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
    adminEventsBroker?.publish(type: 'registered', email: normalizedEmail);
    return Response.ok('Registered');
  })
  ..post('/auth/login', (Request request) async {
    await accessControlService.sync();
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

    final tokens = await _createSessionTokens(db, user);

    return Response.ok(jsonEncode(tokens.toJson()), headers: _jsonHeaders);
  })
  ..post('/auth/refresh', (Request request) async {
    await accessControlService.sync();
    final data = await _readJsonObject(request);
    if (data == null) {
      return Response.badRequest(body: 'Invalid JSON body');
    }

    final refreshToken = _readRequiredString(data, 'refreshToken');
    if (refreshToken == null) {
      return Response.badRequest(body: 'Missing refreshToken');
    }

    final refreshTokenHash = await hashRefreshToken(refreshToken);
    final session = await db.getAuthSessionByRefreshTokenHash(refreshTokenHash);
    if (session == null) {
      return Response.forbidden('Invalid refresh token');
    }

    if (session.revokedAt != null) {
      return Response.forbidden('Invalid refresh token');
    }

    final expiresAt = DateTime.tryParse(session.expiresAt);
    if (expiresAt == null) {
      return Response.forbidden('Invalid refresh token');
    }

    final now = _nowUtc();
    if (!expiresAt.isAfter(now)) {
      return Response.forbidden('Refresh token expired');
    }

    final user = await db.getUserById(session.userId);
    if (user == null) {
      return Response.forbidden('User not found');
    }

    final newRefreshToken = generateRefreshToken();
    final newRefreshTokenHash = await hashRefreshToken(newRefreshToken);
    final newExpiresAt = now.add(refreshTokenLifetime);
    final nowTimestamp = _timestamp(now);

    await db.rotateAuthSessionRefreshToken(
      sessionId: session.id,
      refreshTokenHash: newRefreshTokenHash,
      expiresAt: _timestamp(newExpiresAt),
      lastUsedAt: nowTimestamp,
    );

    final accessToken = generateAccessToken(
      userId: user.id,
      email: user.email,
      sessionId: session.id,
    );

    return Response.ok(
      jsonEncode({'accessToken': accessToken, 'refreshToken': newRefreshToken}),
      headers: _jsonHeaders,
    );
  })
  ..get('/auth/me', (Request request) async {
    try {
      final authContext = await authenticateRequest(
        request,
        db,
        accessControlService,
      );
      return Response.ok(
        jsonEncode({
          'uid': authContext.user.id,
          'email': authContext.user.email,
          'role': authContext.user.role.wireName,
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
  ..post('/auth/logout', (Request request) async {
    try {
      await accessControlService.sync();
      final verifiedToken = readVerifiedAccessToken(request);
      final session = await db.getAuthSessionById(verifiedToken.sessionId);
      if (session != null && session.userId != verifiedToken.userId) {
        return Response.forbidden('Invalid token');
      }

      await db.revokeAuthSession(
        sessionId: verifiedToken.sessionId,
        revokedAt: _timestamp(_nowUtc()),
      );
      return Response.ok('Logged out');
    } on RequestAuthenticationException catch (e) {
      return e.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..post('/auth/change-password', (Request request) async {
    try {
      final authContext = await authenticateRequest(
        request,
        db,
        accessControlService,
      );
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
      await db.revokeAllAuthSessionsForUser(
        userId: authContext.user.id,
        revokedAt: _timestamp(_nowUtc()),
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

String? _readRequiredString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String) {
    return null;
  }

  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Future<_SessionTokens> _createSessionTokens(
  DatabaseService db,
  DbUser user,
) async {
  final now = _nowUtc();
  final sessionId = generateSessionId();
  final refreshToken = generateRefreshToken();
  final refreshTokenHash = await hashRefreshToken(refreshToken);

  await db.createAuthSession(
    sessionId: sessionId,
    userId: user.id,
    refreshTokenHash: refreshTokenHash,
    createdAt: _timestamp(now),
    expiresAt: _timestamp(now.add(refreshTokenLifetime)),
    lastUsedAt: _timestamp(now),
  );

  final accessToken = generateAccessToken(
    userId: user.id,
    email: user.email,
    sessionId: sessionId,
  );

  return _SessionTokens(accessToken: accessToken, refreshToken: refreshToken);
}

DateTime _nowUtc() => DateTime.now().toUtc();

String _timestamp(DateTime value) => value.toUtc().toIso8601String();

class _SessionTokens {
  const _SessionTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  Map<String, String> toJson() {
    return {'accessToken': accessToken, 'refreshToken': refreshToken};
  }
}
