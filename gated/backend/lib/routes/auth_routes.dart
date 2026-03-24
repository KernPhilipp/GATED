import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

import '../auth/allowlist.dart';
import '../auth/hashing.dart';
import '../auth/jwt_service.dart';
import '../db/database.dart';

Router buildAuthRouter(DatabaseService db) => Router()
  ..post('/auth/register', (Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);

    final email = data['email'];
    final password = data['password'];

    if (email == null || password == null) {
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
    final body = await request.readAsString();
    final data = jsonDecode(body);

    final email = data['email'];
    final password = data['password'];

    if (email == null || password == null) {
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
      final authContext = await _authenticateRequest(request, db);
      return Response.ok(
        jsonEncode({
          'uid': authContext.user.id,
          'email': authContext.user.email,
          'createdAt': authContext.user.createdAt,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } on _AuthRouteException catch (e) {
      return e.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..post('/auth/change-password', (Request request) async {
    try {
      final authContext = await _authenticateRequest(request, db);
      final body = await request.readAsString();
      final data = jsonDecode(body);

      final currentPassword = data['currentPassword'];
      final newPassword = data['newPassword'];

      if (currentPassword is! String || newPassword is! String) {
        return Response.badRequest(body: 'Missing data');
      }

      if (currentPassword.isEmpty || newPassword.isEmpty) {
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
    } on _AuthRouteException catch (e) {
      return e.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  });

Future<_AuthContext> _authenticateRequest(
  Request request,
  DatabaseService db,
) async {
  final authHeader = request.headers['Authorization'];

  if (authHeader == null || !authHeader.startsWith('Bearer ')) {
    throw _AuthRouteException(Response.forbidden('No token'));
  }

  final token = authHeader.substring(7);

  try {
    final jwt = verifyJwt(token);
    final rawUserId = jwt.payload['uid'];
    final userId = rawUserId is int ? rawUserId : int.tryParse('$rawUserId');

    if (userId == null) {
      throw _AuthRouteException(Response.forbidden('Invalid token'));
    }

    final user = await db.getUserById(userId);
    if (user == null) {
      throw _AuthRouteException(Response.forbidden('User not found'));
    }

    return _AuthContext(user: user);
  } on JWTExpiredException {
    throw _AuthRouteException(Response.forbidden('Token expired'));
  } on JWTInvalidException {
    throw _AuthRouteException(Response.forbidden('Invalid token'));
  }
}

class _AuthContext {
  const _AuthContext({required this.user});

  final DbUser user;
}

class _AuthRouteException implements Exception {
  const _AuthRouteException(this.response);

  final Response response;
}
