import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/email_access_control.dart';
import '../auth/hashing.dart';
import '../auth/request_auth.dart';
import '../db/database.dart';
import 'admin_events.dart';
import 'request_helpers.dart';

Router buildAdminRouter(
  DatabaseService db,
  EmailAccessControlService accessControlService,
) {
  final eventsBroker = AdminEventsBroker();

  return buildAdminRouterWithEvents(db, accessControlService, eventsBroker);
}

Router buildAdminRouterWithEvents(
  DatabaseService db,
  EmailAccessControlService accessControlService,
  AdminEventsBroker eventsBroker,
) => Router()
  ..get('/admin/users', (Request request) async {
    try {
      await authenticateAdminRequest(request, db, accessControlService);
      final snapshot = await accessControlService.snapshot();
      final users = await db.getAllUsers();
      final usersByEmail = {
        for (final user in users) normalizeEmail(user.email): user,
      };
      final emails = {
        ...snapshot.allowedEmails,
        snapshot.primaryAdminEmail,
      }.toList()..sort((a, b) => a.compareTo(b));

      return Response.ok(
        jsonEncode(
          emails.map((email) {
            final user = usersByEmail[email];
            final role = snapshot.roleForEmail(email) ?? DbUserRole.user;
            return {
              'id': user?.id,
              'email': email,
              'role': role.wireName,
              'isRegistered': user != null,
              'createdAt': user?.createdAt,
            };
          }).toList(),
        ),
        headers: jsonHeaders,
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

      await accessControlService.removeAllowedEmail(targetUser.email);
      eventsBroker.publish(type: 'deleted', email: targetUser.email);

      return Response(204);
    } on RequestAuthenticationException catch (error) {
      return error.response;
    } on EmailAccessControlWriteException catch (error) {
      return _responseForWriteError(error);
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
      eventsBroker.publish(type: 'password-reset', email: targetUser.email);

      return Response.ok(
        jsonEncode({
          'email': targetUser.email,
          'temporaryPassword': temporaryPassword,
        }),
        headers: jsonHeaders,
      );
    } on RequestAuthenticationException catch (error) {
      return error.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..post('/admin/allowed-emails', (Request request) async {
    try {
      await authenticateAdminRequest(request, db, accessControlService);
      final data = await readJsonObject(request);
      final email = readRequiredString(data, 'email');
      if (email == null) {
        return Response.badRequest(body: 'Missing email');
      }

      await accessControlService.addAllowedEmail(email);
      eventsBroker.publish(type: 'allowed-created', email: email);
      return Response(201);
    } on RequestAuthenticationException catch (error) {
      return error.response;
    } on EmailAccessControlWriteException catch (error) {
      return _responseForWriteError(error);
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..put('/admin/allowed-emails/<email>', (
    Request request,
    String encodedEmail,
  ) async {
    try {
      await authenticateAdminRequest(request, db, accessControlService);
      final data = await readJsonObject(request);
      final newEmail = readRequiredString(data, 'email');
      if (newEmail == null) {
        return Response.badRequest(body: 'Missing email');
      }

      final currentEmail = Uri.decodeComponent(encodedEmail);
      await accessControlService.updateAllowedEmail(
        currentEmail: currentEmail,
        newEmail: newEmail,
      );
      eventsBroker.publish(type: 'allowed-updated', email: newEmail);
      return Response.ok('Updated');
    } on RequestAuthenticationException catch (error) {
      return error.response;
    } on EmailAccessControlWriteException catch (error) {
      return _responseForWriteError(error);
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..delete('/admin/allowed-emails/<email>', (
    Request request,
    String encodedEmail,
  ) async {
    try {
      await authenticateAdminRequest(request, db, accessControlService);
      final email = Uri.decodeComponent(encodedEmail);
      await accessControlService.removeAllowedEmail(email);
      eventsBroker.publish(type: 'allowed-deleted', email: email);
      return Response(204);
    } on RequestAuthenticationException catch (error) {
      return error.response;
    } on EmailAccessControlWriteException catch (error) {
      return _responseForWriteError(error);
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

Response _responseForWriteError(EmailAccessControlWriteException error) {
  return switch (error.error) {
    EmailAccessControlWriteError.invalidEmail => Response.badRequest(
      body: 'Invalid email',
    ),
    EmailAccessControlWriteError.emailNotAllowed => Response.notFound(
      'Email not found',
    ),
    EmailAccessControlWriteError.emailAlreadyAllowed ||
    EmailAccessControlWriteError.emailAlreadyRegistered ||
    EmailAccessControlWriteError.primaryAdminCannotBeModified => Response(
      409,
      body: 'Email cannot be modified',
    ),
  };
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
