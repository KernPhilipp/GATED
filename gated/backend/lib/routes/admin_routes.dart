import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/email_access_control.dart';
import '../auth/hashing.dart';
import '../auth/request_auth.dart';
import '../db/database.dart';

Router buildAdminRouter(
  DatabaseService db,
  EmailAccessControlService accessControlService,
) => Router()
  ..get('/admin/users', (Request request) async {
    try {
      await authenticateAdminRequest(request, db, accessControlService);
      final users = await db.getAllUsers();
      return Response.ok(
        jsonEncode(
          users
              .map(
                (user) => {
                  'id': user.id,
                  'email': user.email,
                  'role': user.role.wireName,
                  'createdAt': user.createdAt,
                },
              )
              .toList(),
        ),
        headers: {'Content-Type': 'application/json'},
      );
    } on RequestAuthenticationException catch (error) {
      return error.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..delete('/admin/users/<id>', (Request request, String id) async {
    try {
      await authenticateAdminRequest(request, db, accessControlService);
      final targetUser = await _readTargetUser(db, id);
      if (targetUser == null) {
        return Response.notFound('User not found');
      }

      if (targetUser.role == DbUserRole.admin) {
        return Response(409, body: 'Admin users cannot be modified');
      }

      final deleted = await db.deleteUserById(targetUser.id);
      if (!deleted) {
        return Response.notFound('User not found');
      }

      return Response(204);
    } on RequestAuthenticationException catch (error) {
      return error.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..post('/admin/users/<id>/reset-password', (
    Request request,
    String id,
  ) async {
    try {
      await authenticateAdminRequest(request, db, accessControlService);
      final targetUser = await _readTargetUser(db, id);
      if (targetUser == null) {
        return Response.notFound('User not found');
      }

      if (targetUser.role == DbUserRole.admin) {
        return Response(409, body: 'Admin users cannot be modified');
      }

      final temporaryPassword = _generateTemporaryPassword();
      final hash = await hashPassword(temporaryPassword);
      await db.updateUserPassword(
        userId: targetUser.id,
        passwordHash: hash.hashBase64,
        salt: hash.saltBase64,
      );
      await db.revokeAllAuthSessionsForUser(
        userId: targetUser.id,
        revokedAt: DateTime.now().toUtc().toIso8601String(),
      );

      return Response.ok(
        jsonEncode({
          'email': targetUser.email,
          'temporaryPassword': temporaryPassword,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } on RequestAuthenticationException catch (error) {
      return error.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  });

Future<DbUser?> _readTargetUser(DatabaseService db, String rawId) async {
  final id = int.tryParse(rawId);
  if (id == null || id <= 0) {
    return null;
  }

  return db.getUserById(id);
}

String _generateTemporaryPassword({int length = 16}) {
  const alphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#\$%&*?';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}
