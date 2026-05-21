import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gated_backend/auth/email_access_control.dart';
import 'package:gated_backend/auth/jwt_service.dart';
import 'package:gated_backend/db/database.dart';
import 'package:gated_backend/garage_door/garage_door_service.dart';
import 'package:gated_backend/routes/admin_events.dart';
import 'package:gated_backend/routes/auth_routes.dart';
import 'package:gated_backend/routes/garage_door_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

void main() {
  const email = 'philipp.kern.student@htl-hallein.at';
  const password = 'Secret123!';

  late DatabaseService db;
  late _FakeShellyRelayClient shellyClient;
  late GarageDoorService garageDoorService;
  late AdminEventsBroker adminEventsBroker;
  late Handler handler;
  late Directory tempDir;
  late EmailAccessControlService accessControlService;

  void rebuildHandler() {
    garageDoorService = GarageDoorService(
      config: const GarageDoorConfig(
        shellyBaseUrl: 'http://192.168.0.102',
        switchId: '0',
        inputId: '0',
        shellyRequestTimeout: Duration(seconds: 1),
        statusRefreshDebounce: Duration(milliseconds: 50),
        shellyPollInterval: Duration(milliseconds: 10),
        pulseDuration: Duration(milliseconds: 30),
      ),
      shellyClient: shellyClient,
    );

    handler = Cascade()
        .add(buildAuthRouter(db, accessControlService).call)
        .add(
          buildGarageDoorRouter(
            garageDoorService,
            db,
            accessControlService,
            adminEventsBroker,
          ).call,
        )
        .add(adminEventsBroker.handler(db, accessControlService))
        .handler;
  }

  setUp(() {
    loadJwtEnv(overrideSecret: 'test-jwt-secret');
    db = DatabaseService.openInMemory();
    tempDir = Directory.systemTemp.createTempSync('gated-garage-test-');
    File('${tempDir.path}/allowed_emails.txt').writeAsStringSync('$email\n');
    accessControlService = EmailAccessControlService(
      db: db,
      allowedEmailsFilePath: '${tempDir.path}/allowed_emails.txt',
    );
    adminEventsBroker = AdminEventsBroker();
    shellyClient = _FakeShellyRelayClient();
    rebuildHandler();
  });

  tearDown(() {
    garageDoorService.dispose();
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  test('sensor input false is reported as closed', () async {
    final tokens = await _registerAndLogin(
      handler,
      email: email,
      password: password,
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));
    final response = await _send(
      handler,
      'GET',
      '/garage-door/status',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    final body = await _readJson(response);

    expect(body['state'], 'closed');
    expect(body.containsKey('stateConfidence'), false);
    expect(body.containsKey('remainingMs'), false);
    expect(body.containsKey('countdownLabel'), false);
    expect((body['shelly'] as Map<String, dynamic>)['inputState'], false);
    expect(
      (body['shelly'] as Map<String, dynamic>)['isDoorClosedBySensor'],
      true,
    );
  });

  test('sensor input true is reported as open', () async {
    final tokens = await _registerAndLogin(
      handler,
      email: email,
      password: password,
    );
    shellyClient.inputState = true;

    await Future<void>.delayed(const Duration(milliseconds: 80));
    final response = await _send(
      handler,
      'GET',
      '/garage-door/status',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    final body = await _readJson(response);

    expect(body['state'], 'open');
    expect(
      (body['shelly'] as Map<String, dynamic>)['isDoorClosedBySensor'],
      false,
    );
  });

  test('missing sensor value is reported as unknown', () async {
    final tokens = await _registerAndLogin(
      handler,
      email: email,
      password: password,
    );
    shellyClient.inputState = null;

    await Future<void>.delayed(const Duration(milliseconds: 80));
    final response = await _send(
      handler,
      'GET',
      '/garage-door/status',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    final body = await _readJson(response);

    expect(body['state'], 'unknown');
    expect((body['shelly'] as Map<String, dynamic>)['inputState'], isNull);
  });

  test(
    'trigger waits for a real sensor change before confirming state',
    () async {
      final tokens = await _registerAndLogin(
        handler,
        email: email,
        password: password,
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final triggerResponse = await _send(
        handler,
        'POST',
        '/garage-door/trigger',
        headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
      );
      final triggerBody = await _readJson(triggerResponse);

      expect(triggerResponse.statusCode, 200);
      expect(triggerBody['state'], 'unknown');
      expect(shellyClient.triggerCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      final unchangedResponse = await _send(
        handler,
        'GET',
        '/garage-door/status',
        headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
      );
      expect((await _readJson(unchangedResponse))['state'], 'unknown');

      shellyClient.inputState = true;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final openResponse = await _send(
        handler,
        'GET',
        '/garage-door/status',
        headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
      );
      expect((await _readJson(openResponse))['state'], 'open');
    },
  );

  test('second trigger while status is unknown is rejected', () async {
    final tokens = await _registerAndLogin(
      handler,
      email: email,
      password: password,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final firstTrigger = await _send(
      handler,
      'POST',
      '/garage-door/trigger',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    expect(firstTrigger.statusCode, 200);

    final secondTrigger = await _send(
      handler,
      'POST',
      '/garage-door/trigger',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    expect(secondTrigger.statusCode, 409);
  });

  test('trigger is rejected while sensor value is unavailable', () async {
    final tokens = await _registerAndLogin(
      handler,
      email: email,
      password: password,
    );
    shellyClient.inputState = null;
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final response = await _send(
      handler,
      'POST',
      '/garage-door/trigger',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );

    expect(response.statusCode, 409);
    expect(shellyClient.triggerCount, 0);
  });

  test(
    'shelly trigger failures return a proxy error without state transition',
    () async {
      final tokens = await _registerAndLogin(
        handler,
        email: email,
        password: password,
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      shellyClient.failTrigger = true;

      final triggerResponse = await _send(
        handler,
        'POST',
        '/garage-door/trigger',
        headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
      );

      expect(triggerResponse.statusCode, 502);

      final statusResponse = await _send(
        handler,
        'GET',
        '/garage-door/status',
        headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
      );
      expect((await _readJson(statusResponse))['state'], 'closed');
    },
  );

  test(
    'admin config endpoint validates and persists Shelly base URL',
    () async {
      final tokens = await _registerAndLogin(
        handler,
        email: email,
        password: password,
      );

      final invalidResponse = await _sendJson(
        handler,
        'PUT',
        '/garage-door/config',
        {'shellyBaseUrl': 'ftp://192.168.0.10'},
        headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
      );
      expect(invalidResponse.statusCode, 400);

      final missingHostResponse = await _sendJson(
        handler,
        'PUT',
        '/garage-door/config',
        {'shellyBaseUrl': 'http://'},
        headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
      );
      expect(missingHostResponse.statusCode, 400);

      final updateResponse = await _sendJson(
        handler,
        'PUT',
        '/garage-door/config',
        {'shellyBaseUrl': 'http://192.168.0.200'},
        headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
      );
      expect(updateResponse.statusCode, 200);
      final updateBody = await _readJson(updateResponse);
      expect(updateBody['shellyBaseUrl'], 'http://192.168.0.200');

      final persisted = await db.getGarageDoorConfig(
        defaults: garageDoorService.getConfig().toDbConfig(),
      );
      expect(persisted.shellyBaseUrl, 'http://192.168.0.200');
    },
  );

  test('admin config update publishes admin event', () async {
    final tokens = await _registerAndLogin(
      handler,
      email: email,
      password: password,
    );
    final server = await shelf_io.serve(
      handler,
      InternetAddress.loopbackIPv4,
      0,
    );

    WebSocket? socket;
    try {
      socket = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/admin/events'
        '?accessToken=${tokens.accessToken}',
      );
      final eventFuture = socket.first.timeout(const Duration(seconds: 2));

      final updateResponse = await _sendJson(
        handler,
        'PUT',
        '/garage-door/config',
        {'shellyBaseUrl': 'http://192.168.0.210'},
        headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
      );
      expect(updateResponse.statusCode, 200);

      final event = jsonDecode(await eventFuture as String);
      expect(event['type'], 'garage-door-config-updated');
      expect(event.containsKey('at'), true);
    } finally {
      await socket?.close();
      await server.close(force: true);
    }
  });

  test('invalid persisted Shelly base URL falls back to defaults', () {
    const defaults = GarageDoorConfig(
      shellyBaseUrl: 'http://192.168.0.102',
      switchId: '0',
      inputId: '0',
      shellyRequestTimeout: Duration(seconds: 1),
      statusRefreshDebounce: Duration(milliseconds: 50),
      shellyPollInterval: Duration(milliseconds: 10),
      pulseDuration: Duration(milliseconds: 30),
    );

    final effective = defaults.withRuntimeConfig(
      const DbGarageDoorConfig(shellyBaseUrl: 'http://'),
    );

    expect(effective.shellyBaseUrl, defaults.shellyBaseUrl);
  });

  test('invalid Shelly client base URL becomes a handled Shelly error', () {
    final client = HttpShellyRelayClient(
      baseUrl: 'http://',
      switchId: '0',
      inputId: '0',
      timeout: const Duration(milliseconds: 10),
    );

    expect(client.fetchStatus(), throwsA(isA<GarageDoorShellyException>()));
  });

  test('garage door config endpoint requires admin access', () async {
    const userEmail = 'standard.user@example.com';
    await accessControlService.addAllowedEmail(userEmail);
    final tokens = await _registerAndLogin(
      handler,
      email: userEmail,
      password: password,
    );

    final response = await _send(
      handler,
      'GET',
      '/garage-door/config',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    expect(response.statusCode, 403);
  });

  test(
    'shelly polling failure marks reachability and reports unknown',
    () async {
      final tokens = await _registerAndLogin(
        handler,
        email: email,
        password: password,
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      shellyClient.failFetch = true;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final statusResponse = await _send(
        handler,
        'GET',
        '/garage-door/status',
        headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
      );
      final body = await _readJson(statusResponse);

      expect(body['state'], 'unknown');
      expect((body['shelly'] as Map<String, dynamic>)['isReachable'], false);
    },
  );
}

Future<_Tokens> _registerAndLogin(
  Handler handler, {
  required String email,
  required String password,
}) async {
  final registerResponse = await _sendJson(handler, 'POST', '/auth/register', {
    'email': email,
    'password': password,
  });
  expect(registerResponse.statusCode, 200);

  final loginResponse = await _sendJson(handler, 'POST', '/auth/login', {
    'email': email,
    'password': password,
  });
  expect(loginResponse.statusCode, 200);

  final body = await _readJson(loginResponse);
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

class _FakeShellyRelayClient implements ShellyRelayClient {
  int triggerCount = 0;
  bool failTrigger = false;
  bool failFetch = false;
  bool relayOutput = false;
  bool? inputState = false;

  @override
  Future<ShellyStatusSnapshot> fetchStatus() async {
    if (failFetch) {
      throw const GarageDoorShellyException('Shelly polling failed.');
    }

    return ShellyStatusSnapshot(
      checkedAt: DateTime.now().toUtc(),
      relayOutput: relayOutput,
      inputState: inputState,
    );
  }

  @override
  Future<void> triggerPulse(Duration pulseDuration) async {
    if (failTrigger) {
      throw const GarageDoorShellyException('Shelly trigger failed.');
    }

    triggerCount++;
    relayOutput = true;
    Timer(pulseDuration, () {
      relayOutput = false;
    });
  }
}
