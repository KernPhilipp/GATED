import 'dart:convert';

import 'package:gated_backend/auth/jwt_service.dart';
import 'package:gated_backend/auth/request_auth.dart';
import 'package:gated_backend/db/database.dart';
import 'package:gated_backend/routes/auth_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

void main() {
  const email = 'philipp.kern.student@htl-hallein.at';
  const password = 'Secret123!';
  const newPassword = 'EvenBetter456!';

  late DatabaseService db;
  late Handler handler;

  setUp(() {
    loadJwtEnv(overrideSecret: 'test-jwt-secret');
    db = DatabaseService.openInMemory();

    final protectedRouter = Router()
      ..get('/protected', (Request request) async {
        try {
          final authContext = await authenticateRequest(request, db);
          return Response.ok(
            jsonEncode({'uid': authContext.user.id}),
            headers: {'Content-Type': 'application/json'},
          );
        } on RequestAuthenticationException catch (error) {
          return error.response;
        }
      });

    handler = Cascade()
        .add(buildAuthRouter(db).call)
        .add(protectedRouter.call)
        .handler;
  });

  tearDown(() {
    db.close();
  });

  test('login returns access and refresh tokens', () async {
    await _register(handler, email: email, password: password);

    final loginResponse = await _sendJson(handler, 'POST', '/auth/login', {
      'email': email,
      'password': password,
    });

    expect(loginResponse.statusCode, 200);
    final body = await _readJson(loginResponse);
    expect(body['accessToken'], isA<String>());
    expect((body['accessToken'] as String).isNotEmpty, isTrue);
    expect(body['refreshToken'], isA<String>());
    expect((body['refreshToken'] as String).isNotEmpty, isTrue);
  });

  test('refresh rotates refresh tokens and rejects the old token', () async {
    await _register(handler, email: email, password: password);
    final loginTokens = await _login(handler, email: email, password: password);

    final refreshResponse = await _sendJson(handler, 'POST', '/auth/refresh', {
      'refreshToken': loginTokens.refreshToken,
    });

    expect(refreshResponse.statusCode, 200);
    final rotatedTokens = await _readTokens(refreshResponse);
    expect(rotatedTokens.refreshToken, isNot(loginTokens.refreshToken));

    final reusedRefreshResponse = await _sendJson(
      handler,
      'POST',
      '/auth/refresh',
      {'refreshToken': loginTokens.refreshToken},
    );

    expect(reusedRefreshResponse.statusCode, 403);
    expect(await reusedRefreshResponse.readAsString(), 'Invalid refresh token');
  });

  test('logout revokes only the current session', () async {
    await _register(handler, email: email, password: password);
    final sessionA = await _login(handler, email: email, password: password);
    final sessionB = await _login(handler, email: email, password: password);

    final logoutResponse = await _send(
      handler,
      'POST',
      '/auth/logout',
      headers: {'Authorization': 'Bearer ${sessionA.accessToken}'},
    );

    expect(logoutResponse.statusCode, 200);

    final repeatedLogoutResponse = await _send(
      handler,
      'POST',
      '/auth/logout',
      headers: {'Authorization': 'Bearer ${sessionA.accessToken}'},
    );

    expect(repeatedLogoutResponse.statusCode, 200);

    final protectedA = await _send(
      handler,
      'GET',
      '/protected',
      headers: {'Authorization': 'Bearer ${sessionA.accessToken}'},
    );
    expect(protectedA.statusCode, 403);
    expect(await protectedA.readAsString(), 'Session revoked');

    final protectedB = await _send(
      handler,
      'GET',
      '/protected',
      headers: {'Authorization': 'Bearer ${sessionB.accessToken}'},
    );
    expect(protectedB.statusCode, 200);
  });

  test('change-password revokes all sessions for the user', () async {
    await _register(handler, email: email, password: password);
    final sessionA = await _login(handler, email: email, password: password);
    final sessionB = await _login(handler, email: email, password: password);

    final changePasswordResponse = await _sendJson(
      handler,
      'POST',
      '/auth/change-password',
      {'currentPassword': password, 'newPassword': newPassword},
      headers: {'Authorization': 'Bearer ${sessionA.accessToken}'},
    );

    expect(changePasswordResponse.statusCode, 200);

    final protectedA = await _send(
      handler,
      'GET',
      '/protected',
      headers: {'Authorization': 'Bearer ${sessionA.accessToken}'},
    );
    expect(protectedA.statusCode, 403);
    expect(await protectedA.readAsString(), 'Session revoked');

    final protectedB = await _send(
      handler,
      'GET',
      '/protected',
      headers: {'Authorization': 'Bearer ${sessionB.accessToken}'},
    );
    expect(protectedB.statusCode, 403);
    expect(await protectedB.readAsString(), 'Session revoked');

    final oldPasswordLogin = await _sendJson(handler, 'POST', '/auth/login', {
      'email': email,
      'password': password,
    });
    expect(oldPasswordLogin.statusCode, 403);

    final newPasswordLogin = await _sendJson(handler, 'POST', '/auth/login', {
      'email': email,
      'password': newPassword,
    });
    expect(newPasswordLogin.statusCode, 200);
  });
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
  return _readTokens(response);
}

Future<_Tokens> _readTokens(Response response) async {
  final body = await _readJson(response);
  return _Tokens(
    accessToken: body['accessToken'] as String,
    refreshToken: body['refreshToken'] as String,
  );
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
  return await handler(
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
