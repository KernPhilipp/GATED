import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gated_backend/auth/email_access_control.dart';
import 'package:gated_backend/auth/jwt_service.dart';
import 'package:gated_backend/db/database.dart';
import 'package:gated_backend/garage_door/garage_door_service.dart';
import 'package:gated_backend/routes/auth_routes.dart';
import 'package:gated_backend/routes/garage_door_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

void main() {
  const email = 'philipp.kern.student@htl-hallein.at';
  const password = 'Secret123!';

  late DatabaseService db;
  late _FakeShellyRelayClient shellyClient;
  late GarageDoorService garageDoorService;
  late Handler handler;
  late Directory tempDir;
  late EmailAccessControlService accessControlService;

  void rebuildHandler({
    Duration startupDeterminationDuration = const Duration(milliseconds: 200),
  }) {
    garageDoorService = GarageDoorService(
      config: GarageDoorConfig(
        shellyBaseUrl: 'http://192.168.0.102',
        switchId: '0',
        shellyRequestTimeout: const Duration(seconds: 1),
        statusRefreshDebounce: const Duration(milliseconds: 50),
        shellyPollInterval: const Duration(milliseconds: 10),
        selfTriggerSuppressionWindow: const Duration(milliseconds: 80),
        pulseDuration: const Duration(milliseconds: 30),
        openingDuration: const Duration(milliseconds: 120),
        openHoldDuration: const Duration(milliseconds: 120),
        closingDuration: const Duration(milliseconds: 120),
        startupDeterminationDuration: startupDeterminationDuration,
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
          ).call,
        )
        .handler;
  }

  setUp(() {
    loadJwtEnv(overrideSecret: 'test-jwt-secret');
    db = DatabaseService.openInMemory();
    tempDir = Directory.systemTemp.createTempSync('gated-garage-test-');
    File('${tempDir.path}/allowed_emails.txt').writeAsStringSync('$email\n');
    File('${tempDir.path}/admin_emails.txt').writeAsStringSync('');
    accessControlService = EmailAccessControlService(
      db: db,
      allowedEmailsFilePath: '${tempDir.path}/allowed_emails.txt',
      adminEmailsFilePath: '${tempDir.path}/admin_emails.txt',
    );
    shellyClient = _FakeShellyRelayClient();
    rebuildHandler();
  });

  tearDown(() {
    garageDoorService.dispose();
    shellyClient.dispose();
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  test('initial state starts as determining and becomes closed', () async {
    final tokens = await _registerAndLogin(
      handler,
      email: email,
      password: password,
    );
    garageDoorService.dispose();
    rebuildHandler(
      startupDeterminationDuration: const Duration(milliseconds: 200),
    );

    final initialResponse = await _send(
      handler,
      'GET',
      '/garage-door/status',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );

    expect(initialResponse.statusCode, 200);
    final initialBody = await _readJson(initialResponse);
    expect(initialBody['state'], 'determining');
    expect(initialBody['remainingMs'], isA<int>());

    await Future<void>.delayed(const Duration(milliseconds: 260));

    final settledResponse = await _send(
      handler,
      'GET',
      '/garage-door/status',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    final settledBody = await _readJson(settledResponse);
    expect(settledBody['state'], 'closed');
    expect(settledBody['stateConfidence'], 'modeled');
  });

  test('trigger starts modeled cycle and calls Shelly exactly once', () async {
    final tokens = await _registerAndLogin(
      handler,
      email: email,
      password: password,
    );
    await Future<void>.delayed(const Duration(milliseconds: 260));

    final triggerResponse = await _send(
      handler,
      'POST',
      '/garage-door/trigger',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );

    expect(triggerResponse.statusCode, 200);
    final triggerBody = await _readJson(triggerResponse);
    expect(triggerBody['state'], 'opening');
    expect(triggerBody['stateConfidence'], 'modeled');
    expect(shellyClient.triggerCount, 1);

    await Future<void>.delayed(const Duration(milliseconds: 130));
    final openStatus = await _send(
      handler,
      'GET',
      '/garage-door/status',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    expect((await _readJson(openStatus))['state'], 'open');

    await Future<void>.delayed(const Duration(milliseconds: 130));
    final closingStatus = await _send(
      handler,
      'GET',
      '/garage-door/status',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    expect((await _readJson(closingStatus))['state'], 'closing');

    await Future<void>.delayed(const Duration(milliseconds: 130));
    final closedStatus = await _send(
      handler,
      'GET',
      '/garage-door/status',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    expect((await _readJson(closedStatus))['state'], 'closed');
  });

  test(
    'manual state override replaces the modeled state immediately',
    () async {
      final tokens = await _registerAndLogin(
        handler,
        email: email,
        password: password,
      );

      final response = await _sendJson(
        handler,
        'POST',
        '/garage-door/state',
        {'state': 'unknown'},
        headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
      );

      expect(response.statusCode, 200);
      final body = await _readJson(response);
      expect(body['state'], 'unknown');
      expect(body['stateConfidence'], 'modeled');
      expect(
        (body['lastAction'] as Map<String, dynamic>)['type'],
        'manualOverride',
      );
    },
  );

  test(
    'second trigger during movement is rejected deterministically',
    () async {
      final tokens = await _registerAndLogin(
        handler,
        email: email,
        password: password,
      );
      await Future<void>.delayed(const Duration(milliseconds: 260));

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
    },
  );

  test(
    'shelly failures return a proxy error without state transition',
    () async {
      final tokens = await _registerAndLogin(
        handler,
        email: email,
        password: password,
      );
      await Future<void>.delayed(const Duration(milliseconds: 260));
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

  test('external rising edge at closed starts opening heuristically', () async {
    final tokens = await _registerAndLogin(
      handler,
      email: email,
      password: password,
    );
    await Future<void>.delayed(const Duration(milliseconds: 260));

    shellyClient.emitExternalPulse(const Duration(milliseconds: 40));
    await Future<void>.delayed(const Duration(milliseconds: 25));

    final statusResponse = await _send(
      handler,
      'GET',
      '/garage-door/status',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    final body = await _readJson(statusResponse);
    expect(body['state'], 'opening');
    expect(body['stateConfidence'], 'heuristic');
    expect(
      (body['lastAction'] as Map<String, dynamic>)['type'],
      'externalHeuristicTrigger',
    );
    expect(
      (body['lastAction'] as Map<String, dynamic>)['source'],
      'heuristic-external',
    );
  });

  test('external rising edge at open starts closing heuristically', () async {
    final tokens = await _registerAndLogin(
      handler,
      email: email,
      password: password,
    );
    await Future<void>.delayed(const Duration(milliseconds: 260));

    final setOpenResponse = await _sendJson(
      handler,
      'POST',
      '/garage-door/state',
      {'state': 'open'},
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    expect(setOpenResponse.statusCode, 200);

    shellyClient.emitExternalPulse(const Duration(milliseconds: 40));
    await Future<void>.delayed(const Duration(milliseconds: 25));

    final statusResponse = await _send(
      handler,
      'GET',
      '/garage-door/status',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    final body = await _readJson(statusResponse);
    expect(body['state'], 'closing');
    expect(body['stateConfidence'], 'heuristic');
  });

  test(
    'external rising edge during opening sets state to unknown heuristically',
    () async {
      final tokens = await _registerAndLogin(
        handler,
        email: email,
        password: password,
      );
      await Future<void>.delayed(const Duration(milliseconds: 260));

      shellyClient.emitExternalPulse(const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      shellyClient.emitExternalPulse(const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final statusResponse = await _send(
        handler,
        'GET',
        '/garage-door/status',
        headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
      );
      final body = await _readJson(statusResponse);
      expect(body['state'], 'unknown');
      expect(body['stateConfidence'], 'heuristic');
      expect(
        (body['lastAction'] as Map<String, dynamic>)['type'],
        'externalHeuristicTrigger',
      );
    },
  );

  test(
    'own trigger does not get re-classified as external heuristic',
    () async {
      final tokens = await _registerAndLogin(
        handler,
        email: email,
        password: password,
      );
      await Future<void>.delayed(const Duration(milliseconds: 260));

      final triggerResponse = await _send(
        handler,
        'POST',
        '/garage-door/trigger',
        headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
      );
      expect(triggerResponse.statusCode, 200);

      await Future<void>.delayed(const Duration(milliseconds: 40));

      final statusResponse = await _send(
        handler,
        'GET',
        '/garage-door/status',
        headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
      );
      final body = await _readJson(statusResponse);
      expect(body['state'], 'opening');
      expect(body['stateConfidence'], 'modeled');
      expect((body['lastAction'] as Map<String, dynamic>)['type'], 'trigger');
    },
  );

  test('polling without rising edge keeps the state unchanged', () async {
    final tokens = await _registerAndLogin(
      handler,
      email: email,
      password: password,
    );
    await Future<void>.delayed(const Duration(milliseconds: 320));

    final statusResponse = await _send(
      handler,
      'GET',
      '/garage-door/status',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    final body = await _readJson(statusResponse);
    expect(body['state'], 'closed');
    expect(body['stateConfidence'], 'modeled');
  });

  test('shelly polling failure marks reachability but keeps state', () async {
    final tokens = await _registerAndLogin(
      handler,
      email: email,
      password: password,
    );
    await Future<void>.delayed(const Duration(milliseconds: 260));
    shellyClient.failFetch = true;
    await Future<void>.delayed(const Duration(milliseconds: 40));

    final statusResponse = await _send(
      handler,
      'GET',
      '/garage-door/status',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    final body = await _readJson(statusResponse);
    expect(body['state'], 'closed');
    expect((body['shelly'] as Map<String, dynamic>)['isReachable'], false);
  });
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
  final List<Timer> _timers = [];

  void emitExternalPulse(Duration pulseDuration) {
    relayOutput = true;
    _timers.add(
      Timer(pulseDuration, () {
        relayOutput = false;
      }),
    );
  }

  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  @override
  Future<ShellyStatusSnapshot> fetchStatus() async {
    if (failFetch) {
      throw const GarageDoorShellyException('Shelly polling failed.');
    }

    return ShellyStatusSnapshot(
      checkedAt: DateTime.now().toUtc(),
      relayOutput: relayOutput,
      inputState: relayOutput,
    );
  }

  @override
  Future<void> triggerPulse(Duration pulseDuration) async {
    if (failTrigger) {
      throw const GarageDoorShellyException('Shelly trigger failed.');
    }

    triggerCount++;
    emitExternalPulse(pulseDuration);
  }
}
