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
        inputId: '0',
        sensorSettleDuration: const Duration(milliseconds: 50),
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
    accessControlService = EmailAccessControlService(
      db: db,
      allowedEmailsFilePath: '${tempDir.path}/allowed_emails.txt',
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

  test('sensor input false becomes closed after settle delay', () async {
    final tokens = await _registerAndLogin(
      handler,
      email: email,
      password: password,
    );
    garageDoorService.dispose();
    rebuildHandler(
      startupDeterminationDuration: const Duration(milliseconds: 200),
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));

    final settledResponse = await _send(
      handler,
      'GET',
      '/garage-door/status',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    final settledBody = await _readJson(settledResponse);
    expect(settledBody['state'], 'closed');
    expect(settledBody['stateConfidence'], 'sensor');
    expect(
      (settledBody['shelly'] as Map<String, dynamic>)['inputState'],
      false,
    );
    expect(
      (settledBody['shelly'] as Map<String, dynamic>)['isDoorClosedBySensor'],
      true,
    );
  });

  test('trigger opens and closes after sensor confirmation', () async {
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

    shellyClient.inputState = true;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final openStatus = await _send(
      handler,
      'GET',
      '/garage-door/status',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    expect((await _readJson(openStatus))['state'], 'open');

    final closeTrigger = await _send(
      handler,
      'POST',
      '/garage-door/trigger',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    expect(closeTrigger.statusCode, 200);
    shellyClient.inputState = false;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final closedStatus = await _send(
      handler,
      'GET',
      '/garage-door/status',
      headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    expect((await _readJson(closedStatus))['state'], 'closed');
  });

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
    shellyClient.inputState = null;

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
    expect(body.containsKey('lastAction'), false);
    expect(body['lastChangedAt'], isA<String>());
  });

  test('external rising edge at open starts closing heuristically', () async {
    final tokens = await _registerAndLogin(
      handler,
      email: email,
      password: password,
    );
    await Future<void>.delayed(const Duration(milliseconds: 260));
    shellyClient.inputState = true;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    shellyClient.inputState = null;

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
      shellyClient.inputState = null;

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
      expect(body.containsKey('lastAction'), false);
      expect(body['lastChangedAt'], isA<String>());
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
      shellyClient.inputState = null;

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
      expect(body.containsKey('lastAction'), false);
      expect(body['lastChangedAt'], isA<String>());
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
    expect(body['stateConfidence'], 'sensor');
  });

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

  test('invalid persisted Shelly base URL falls back to defaults', () {
    final defaults = GarageDoorConfig(
      shellyBaseUrl: 'http://192.168.0.102',
      switchId: '0',
      inputId: '0',
      sensorSettleDuration: const Duration(milliseconds: 50),
      shellyRequestTimeout: const Duration(seconds: 1),
      statusRefreshDebounce: const Duration(milliseconds: 50),
      shellyPollInterval: const Duration(milliseconds: 10),
      selfTriggerSuppressionWindow: const Duration(milliseconds: 80),
      pulseDuration: const Duration(milliseconds: 30),
      openingDuration: const Duration(milliseconds: 120),
      openHoldDuration: const Duration(milliseconds: 120),
      closingDuration: const Duration(milliseconds: 120),
      startupDeterminationDuration: const Duration(milliseconds: 200),
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
  bool? inputState = false;
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
      inputState: inputState,
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
