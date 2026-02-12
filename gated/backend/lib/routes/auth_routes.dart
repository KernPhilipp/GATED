import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

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
  ..get('/auth/me', (Request request) {
    final authHeader = request.headers['Authorization'];

    if (authHeader == null || !authHeader.startsWith('Bearer')) {
      return Response.forbidden('No token');
    }

    final token = authHeader.substring(7);

    try {
      final jwt = verifyJwt(token);
      return Response.ok(
        jsonEncode(jwt.payload),
        headers: {'Content-Type': 'application/json'},
      );
    } on JWTExpiredException {
      return Response.forbidden('Token expired');
    } on JWTInvalidException {
      return Response.forbidden('Invalid token');
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  });
