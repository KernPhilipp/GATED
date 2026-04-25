import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:gated_backend/auth/email_access_control.dart';
import 'package:gated_backend/auth/jwt_service.dart';
import 'package:gated_backend/db/database.dart';
import 'package:gated_backend/db/license_plate_database.dart';
import 'package:gated_backend/routes/auth_routes.dart';
import 'package:gated_backend/routes/kennzeichen_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

void main() {
  const email = 'philipp.kern.student@htl-hallein.at';
  const password = 'Secret123!';

  late DatabaseService authDb;
  late LicensePlateDatabaseService kennzeichenDb;
  late Handler authHandler;
  late Handler kennzeichenHandler;
  late KennzeichenEventsBroker eventsBroker;
  HttpServer? webSocketServer;
  late Directory tempDir;
  late EmailAccessControlService accessControlService;

  setUp(() async {
    loadJwtEnv(overrideSecret: 'test-jwt-secret');
    authDb = DatabaseService.openInMemory();
    kennzeichenDb = LicensePlateDatabaseService.openInMemory();
    tempDir = Directory.systemTemp.createTempSync('gated-kennzeichen-test-');
    File('${tempDir.path}/allowed_emails.txt').writeAsStringSync('$email\n');
    accessControlService = EmailAccessControlService(
      db: authDb,
      allowedEmailsFilePath: '${tempDir.path}/allowed_emails.txt',
    );
    authHandler = buildAuthRouter(authDb, accessControlService).call;
    eventsBroker = KennzeichenEventsBroker();
    kennzeichenHandler = buildKennzeichenRouter(
      kennzeichenDb,
      authDb,
      eventsBroker,
      accessControlService,
    ).call;
    webSocketServer = await shelf_io.serve(
      eventsBroker.handler(authDb, accessControlService),
      InternetAddress.loopbackIPv4,
      0,
    );
    await _register(authHandler, email: email, password: password);
  });

  tearDown(() async {
    await webSocketServer?.close(force: true);
    kennzeichenDb.close();
    authDb.close();
    tempDir.deleteSync(recursive: true);
  });

  test('websocket broadcasts create, update, and delete events', () async {
    final token = await _login(authHandler, email: email, password: password);
    final socket = await _connectEventsSocket(webSocketServer!, token);
    final events = StreamQueue<dynamic>(socket);

    final createResponse = await _sendAuthorizedJson(
      kennzeichenHandler,
      'POST',
      '/kennzeichen',
      token,
      {'teacherName': 'Tester', 'licensePlate': 'hal123'},
    );
    expect(createResponse.statusCode, 201);

    final createdEntry = await _readJson(createResponse);
    final createdEvent = await _readWebSocketEvent(events);
    expect(createdEvent['type'], 'created');
    expect(createdEvent['id'], createdEntry['id']);

    final updateResponse = await _sendAuthorizedJson(
      kennzeichenHandler,
      'PUT',
      '/kennzeichen/${createdEntry['id']}',
      token,
      {'teacherName': 'Tester Neu', 'licensePlate': 'hal999'},
    );
    expect(updateResponse.statusCode, 200);

    final updatedEvent = await _readWebSocketEvent(events);
    expect(updatedEvent['type'], 'updated');
    expect(updatedEvent['id'], createdEntry['id']);

    final deleteResponse = await _sendAuthorizedRequest(
      kennzeichenHandler,
      'DELETE',
      '/kennzeichen/${createdEntry['id']}',
      token,
    );
    expect(deleteResponse.statusCode, 204);

    final deletedEvent = await _readWebSocketEvent(events);
    expect(deletedEvent['type'], 'deleted');
    expect(deletedEvent['id'], createdEntry['id']);

    await events.cancel();
    await socket.close();
  });

  test('multiple websocket clients receive the same event', () async {
    final token = await _login(authHandler, email: email, password: password);
    final firstSocket = await _connectEventsSocket(webSocketServer!, token);
    final secondSocket = await _connectEventsSocket(webSocketServer!, token);
    final firstEvents = StreamQueue<dynamic>(firstSocket);
    final secondEvents = StreamQueue<dynamic>(secondSocket);

    final createResponse = await _sendAuthorizedJson(
      kennzeichenHandler,
      'POST',
      '/kennzeichen',
      token,
      {'teacherName': 'Broadcast', 'licensePlate': 'hal777'},
    );
    expect(createResponse.statusCode, 201);

    final createdEntry = await _readJson(createResponse);
    final firstEvent = await _readWebSocketEvent(firstEvents);
    final secondEvent = await _readWebSocketEvent(secondEvents);

    expect(firstEvent['type'], 'created');
    expect(secondEvent['type'], 'created');
    expect(firstEvent['id'], createdEntry['id']);
    expect(secondEvent['id'], createdEntry['id']);

    await firstEvents.cancel();
    await secondEvents.cancel();
    await firstSocket.close();
    await secondSocket.close();
  });

  test('websocket rejects unauthenticated connections', () async {
    final port = webSocketServer!.port;
    await expectLater(
      WebSocket.connect('ws://127.0.0.1:$port/kennzeichen/events'),
      throwsA(isA<WebSocketException>()),
    );
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

Future<String> _login(
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
  return body['accessToken'] as String;
}

Future<WebSocket> _connectEventsSocket(HttpServer server, String accessToken) {
  final port = server.port;
  return WebSocket.connect(
    'ws://127.0.0.1:$port/kennzeichen/events?accessToken=$accessToken',
  );
}

Future<Map<String, dynamic>> _readWebSocketEvent(
  StreamQueue<dynamic> events,
) async {
  final rawMessage = await events.next.timeout(const Duration(seconds: 5));
  final decoded = jsonDecode(rawMessage as String);
  return decoded is Map<String, dynamic>
      ? decoded
      : decoded.map((key, value) => MapEntry('$key', value));
}

Future<Response> _sendAuthorizedJson(
  Handler handler,
  String method,
  String path,
  String accessToken,
  Map<String, Object?> body,
) {
  return _send(
    handler,
    method,
    path,
    body: jsonEncode(body),
    headers: {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    },
  );
}

Future<Response> _sendAuthorizedRequest(
  Handler handler,
  String method,
  String path,
  String accessToken,
) {
  return _send(
    handler,
    method,
    path,
    headers: {'Authorization': 'Bearer $accessToken'},
  );
}

Future<Response> _sendJson(
  Handler handler,
  String method,
  String path,
  Map<String, Object?> body,
) {
  return _send(
    handler,
    method,
    path,
    body: jsonEncode(body),
    headers: {'Content-Type': 'application/json'},
  );
}

Future<Map<String, dynamic>> _readJson(Response response) async {
  final body = await response.readAsString();
  final decoded = jsonDecode(body);
  return decoded is Map<String, dynamic>
      ? decoded
      : decoded.map((key, value) => MapEntry('$key', value));
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
