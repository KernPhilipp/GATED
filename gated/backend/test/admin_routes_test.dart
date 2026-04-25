import 'dart:convert';
import 'dart:io';

import 'package:gated_backend/auth/email_access_control.dart';
import 'package:gated_backend/auth/jwt_service.dart';
import 'package:gated_backend/db/database.dart';
import 'package:gated_backend/routes/admin_events.dart';
import 'package:gated_backend/routes/admin_routes.dart';
import 'package:gated_backend/routes/auth_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  const adminEmail = 'admin@example.com';
  const userEmail = 'user@example.com';
  const password = 'Secret123!';

  late DatabaseService db;
  late Directory tempDir;
  late EmailAccessControlService accessControlService;
  late Handler handler;

  setUp(() {
    loadJwtEnv(overrideSecret: 'test-jwt-secret');
    db = DatabaseService.openInMemory();
    tempDir = Directory.systemTemp.createTempSync('gated-admin-test-');
    _writeEmailFiles(tempDir, allowedEmails: {userEmail});
    accessControlService = EmailAccessControlService(
      db: db,
      allowedEmailsFilePath: '${tempDir.path}/allowed_emails.txt',
      primaryAdminEmail: adminEmail,
    );
    final adminEventsBroker = AdminEventsBroker();
    handler = Cascade()
        .add(buildAuthRouter(db, accessControlService, adminEventsBroker).call)
        .add(
          buildAdminRouterWithEvents(
            db,
            accessControlService,
            adminEventsBroker,
          ).call,
        )
        .handler;
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  test(
    'sync updates roles and removes users no longer present in the files',
    () async {
      await _register(handler, email: adminEmail, password: password);
      await _register(handler, email: userEmail, password: password);

      _writeEmailFiles(tempDir, allowedEmails: {adminEmail});
      await accessControlService.sync();

      final unchangedAdmin = await db.getUserByEmail(adminEmail);
      final deletedUser = await db.getUserByEmail(userEmail);
      expect(unchangedAdmin?.role, DbUserRole.admin);
      expect(deletedUser, isNull);

      _writeEmailFiles(tempDir, allowedEmails: const <String>{});
      await accessControlService.sync();

      expect((await db.getUserByEmail(adminEmail))?.role, DbUserRole.admin);
    },
  );

  test('admins can list allowed but unregistered users', () async {
    await _register(handler, email: adminEmail, password: password);
    final adminSession = await _login(
      handler,
      email: adminEmail,
      password: password,
    );

    final listResponse = await _send(
      handler,
      'GET',
      '/admin/users',
      headers: {'Authorization': 'Bearer ${adminSession.accessToken}'},
    );

    expect(listResponse.statusCode, 200);
    final listedUsers = await _readJsonList(listResponse);
    final allowedUser = listedUsers.firstWhere(
      (user) => user['email'] == userEmail,
    );
    expect(allowedUser['role'], 'User');
    expect(allowedUser['isRegistered'], isFalse);
    expect(allowedUser['userId'], isNull);
  });

  test('non-admin users cannot access admin endpoints', () async {
    await _register(handler, email: userEmail, password: password);
    final userSession = await _login(
      handler,
      email: userEmail,
      password: password,
    );

    final response = await _send(
      handler,
      'GET',
      '/admin/users',
      headers: {'Authorization': 'Bearer ${userSession.accessToken}'},
    );

    expect(response.statusCode, 403);
    expect(await response.readAsString(), 'Admin access required');
  });

  test('admins can list users but cannot delete other admins', () async {
    await _register(handler, email: adminEmail, password: password);
    await _register(handler, email: userEmail, password: password);
    final adminSession = await _login(
      handler,
      email: adminEmail,
      password: password,
    );

    final listResponse = await _send(
      handler,
      'GET',
      '/admin/users',
      headers: {'Authorization': 'Bearer ${adminSession.accessToken}'},
    );
    expect(listResponse.statusCode, 200);
    final listedUsers = await _readJsonList(listResponse);
    expect(listedUsers, hasLength(2));

    final adminUser = listedUsers.firstWhere(
      (user) => user['email'] == adminEmail,
    );
    final deleteAdminResponse = await _send(
      handler,
      'DELETE',
      '/admin/users/${adminUser['id']}',
      headers: {'Authorization': 'Bearer ${adminSession.accessToken}'},
    );
    expect(deleteAdminResponse.statusCode, 409);
  });

  test(
    'deleting a registered user removes the allowed email and blocks re-registration',
    () async {
      await _register(handler, email: adminEmail, password: password);
      await _register(handler, email: userEmail, password: password);
      final adminSession = await _login(
        handler,
        email: adminEmail,
        password: password,
      );
      final user = await db.getUserByEmail(userEmail);

      final deleteResponse = await _send(
        handler,
        'DELETE',
        '/admin/users/${user!.id}',
        headers: {'Authorization': 'Bearer ${adminSession.accessToken}'},
      );
      expect(deleteResponse.statusCode, 204);
      expect(await db.getUserByEmail(userEmail), isNull);
      expect(_readAllowedEmails(tempDir), isNot(contains(userEmail)));

      final registerAgain = await _sendJson(handler, 'POST', '/auth/register', {
        'email': userEmail,
        'password': password,
      });
      expect(registerAgain.statusCode, 403);
    },
  );

  test('admins can add and edit allowed emails', () async {
    await _register(handler, email: adminEmail, password: password);
    await _register(handler, email: userEmail, password: password);
    final adminSession = await _login(
      handler,
      email: adminEmail,
      password: password,
    );

    final addResponse = await _sendJson(
      handler,
      'POST',
      '/admin/allowed-emails',
      {'email': 'new-user@example.com'},
      headers: {'Authorization': 'Bearer ${adminSession.accessToken}'},
    );
    expect(addResponse.statusCode, 201);
    expect(_readAllowedEmails(tempDir), contains('new-user@example.com'));

    final editResponse = await _sendJson(
      handler,
      'PUT',
      '/admin/allowed-emails/${Uri.encodeComponent(userEmail)}',
      {'email': 'renamed@example.com'},
      headers: {'Authorization': 'Bearer ${adminSession.accessToken}'},
    );
    expect(editResponse.statusCode, 200);
    expect(await db.getUserByEmail(userEmail), isNull);
    expect(await db.getUserByEmail('renamed@example.com'), isNotNull);
    expect(_readAllowedEmails(tempDir), contains('renamed@example.com'));
    expect(_readAllowedEmails(tempDir), isNot(contains(userEmail)));
  });

  test(
    'primary admin is fixed and cannot be modified through the allowlist',
    () async {
      await _register(handler, email: adminEmail, password: password);
      final adminSession = await _login(
        handler,
        email: adminEmail,
        password: password,
      );

      final addAdminResponse = await _sendJson(
        handler,
        'POST',
        '/admin/allowed-emails',
        {'email': adminEmail},
        headers: {'Authorization': 'Bearer ${adminSession.accessToken}'},
      );
      expect(addAdminResponse.statusCode, 409);

      final listResponse = await _send(
        handler,
        'GET',
        '/admin/users',
        headers: {'Authorization': 'Bearer ${adminSession.accessToken}'},
      );
      final listedUsers = await _readJsonList(listResponse);
      final adminUser = listedUsers.firstWhere(
        (user) => user['email'] == adminEmail,
      );
      expect(adminUser['role'], 'Admin');
    },
  );

  test(
    'reset-password invalidates old sessions and allows login with the new password',
    () async {
      await _register(handler, email: adminEmail, password: password);
      await _register(handler, email: userEmail, password: password);

      final adminSession = await _login(
        handler,
        email: adminEmail,
        password: password,
      );
      final userSession = await _login(
        handler,
        email: userEmail,
        password: password,
      );

      final user = await db.getUserByEmail(userEmail);
      final resetResponse = await _send(
        handler,
        'POST',
        '/admin/users/${user!.id}/reset-password',
        headers: {'Authorization': 'Bearer ${adminSession.accessToken}'},
      );

      expect(resetResponse.statusCode, 200);
      final body = await _readJson(resetResponse);
      expect(body['email'], userEmail);
      expect(body['temporaryPassword'], isA<String>());

      final meResponse = await _send(
        handler,
        'GET',
        '/auth/me',
        headers: {'Authorization': 'Bearer ${userSession.accessToken}'},
      );
      expect(meResponse.statusCode, 403);
      expect(await meResponse.readAsString(), 'Session revoked');

      final oldLogin = await _sendJson(handler, 'POST', '/auth/login', {
        'email': userEmail,
        'password': password,
      });
      expect(oldLogin.statusCode, 403);

      final newLogin = await _sendJson(handler, 'POST', '/auth/login', {
        'email': userEmail,
        'password': body['temporaryPassword'] as String,
      });
      expect(newLogin.statusCode, 200);
    },
  );
}

void _writeEmailFiles(Directory tempDir, {required Set<String> allowedEmails}) {
  File(
    '${tempDir.path}/allowed_emails.txt',
  ).writeAsStringSync('${allowedEmails.join('\n')}\n');
}

Set<String> _readAllowedEmails(Directory tempDir) {
  return File('${tempDir.path}/allowed_emails.txt')
      .readAsLinesSync()
      .where((line) => line.trim().isNotEmpty)
      .map((line) => line.trim())
      .toSet();
}

Future<void> _register(
  Handler handler, {
  required String email,
  required String password,
}) async {
  final response = await _sendJson(handler, 'POST', '/auth/register', {
    'email': email,
    'password': password,
  });
  expect(response.statusCode, 200);
}

Future<_Tokens> _login(
  Handler handler, {
  required String email,
  required String password,
}) async {
  final response = await _sendJson(handler, 'POST', '/auth/login', {
    'email': email,
    'password': password,
  });
  expect(response.statusCode, 200);
  final body = await _readJson(response);
  return _Tokens(
    accessToken: body['accessToken'] as String,
    refreshToken: body['refreshToken'] as String,
  );
}

Future<List<Map<String, dynamic>>> _readJsonList(Response response) async {
  final body = await response.readAsString();
  final decoded = jsonDecode(body) as List<dynamic>;
  return decoded.map<Map<String, dynamic>>((entry) {
    return (entry as Map).map((key, value) => MapEntry('$key', value));
  }).toList();
}

Future<Map<String, dynamic>> _readJson(Response response) async {
  final body = await response.readAsString();
  final decoded = jsonDecode(body);
  return decoded is Map<String, dynamic>
      ? decoded
      : decoded.map((key, value) => MapEntry('$key', value));
}

Future<Response> _sendJson(
  Handler handler,
  String method,
  String path,
  Map<String, Object?> body, {
  Map<String, String>? headers,
}) {
  return _send(
    handler,
    method,
    path,
    body: jsonEncode(body),
    headers: {'Content-Type': 'application/json', ...?headers},
  );
}

Future<Response> _send(
  Handler handler,
  String method,
  String path, {
  String? body,
  Map<String, String>? headers,
}) async {
  return handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: headers,
      body: body ?? '',
    ),
  );
}

class _Tokens {
  const _Tokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}
