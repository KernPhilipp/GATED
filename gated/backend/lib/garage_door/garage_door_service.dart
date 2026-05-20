import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';

import '../db/database.dart';

enum GarageDoorState { open, closed, unknown }

class GarageDoorConfig {
  const GarageDoorConfig({
    required this.shellyBaseUrl,
    required this.switchId,
    required this.inputId,
    required this.shellyRequestTimeout,
    required this.statusRefreshDebounce,
    required this.shellyPollInterval,
    required this.pulseDuration,
  });

  factory GarageDoorConfig.fromEnvironment() {
    final dotEnv = DotEnv();
    if (File('.env').existsSync()) {
      dotEnv.load();
    }

    String readString(String key, String defaultValue) {
      final envValue = dotEnv[key] ?? Platform.environment[key];
      final trimmed = envValue?.trim();
      return trimmed == null || trimmed.isEmpty ? defaultValue : trimmed;
    }

    int readSeconds(String key, int defaultValue) {
      final rawValue = readString(key, '$defaultValue');
      final parsed = int.tryParse(rawValue);
      if (parsed == null || parsed < 0) {
        return defaultValue;
      }
      return parsed;
    }

    int readMilliseconds(String key, int defaultValue) {
      final rawValue = readString(key, '$defaultValue');
      final parsed = int.tryParse(rawValue);
      if (parsed == null || parsed < 0) {
        return defaultValue;
      }
      return parsed;
    }

    return GarageDoorConfig(
      shellyBaseUrl: readString('SHELLY_BASE_URL', 'http://192.168.0.102'),
      switchId: readString('SHELLY_SWITCH_ID', '0'),
      inputId: readString('SHELLY_INPUT_ID', '0'),
      shellyRequestTimeout: Duration(
        seconds: readSeconds('SHELLY_REQUEST_TIMEOUT_SECONDS', 3),
      ),
      statusRefreshDebounce: Duration(
        seconds: readSeconds('GARAGE_DOOR_STATUS_REFRESH_SECONDS', 2),
      ),
      shellyPollInterval: Duration(
        milliseconds: readMilliseconds('GARAGE_DOOR_SHELLY_POLL_MS', 250),
      ),
      pulseDuration: Duration(
        seconds: readSeconds('GARAGE_DOOR_PULSE_SECONDS', 1),
      ),
    );
  }

  final String shellyBaseUrl;
  final String switchId;
  final String inputId;
  final Duration shellyRequestTimeout;
  final Duration statusRefreshDebounce;
  final Duration shellyPollInterval;
  final Duration pulseDuration;

  GarageDoorConfig copyWith({String? shellyBaseUrl}) {
    return GarageDoorConfig(
      shellyBaseUrl: shellyBaseUrl?.trim() ?? this.shellyBaseUrl,
      switchId: switchId,
      inputId: inputId,
      shellyRequestTimeout: shellyRequestTimeout,
      statusRefreshDebounce: statusRefreshDebounce,
      shellyPollInterval: shellyPollInterval,
      pulseDuration: pulseDuration,
    );
  }

  GarageDoorConfig withRuntimeConfig(DbGarageDoorConfig config) {
    final runtimeBaseUrl = config.shellyBaseUrl.trim();
    if (!isValidShellyBaseUrl(runtimeBaseUrl)) {
      return this;
    }
    return copyWith(shellyBaseUrl: runtimeBaseUrl);
  }

  DbGarageDoorConfig toDbConfig() {
    return DbGarageDoorConfig(shellyBaseUrl: shellyBaseUrl);
  }

  Map<String, Object?> toPublicJson() {
    return {'shellyBaseUrl': shellyBaseUrl};
  }

  static bool isValidShellyBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.isAbsolute &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.trim().isNotEmpty;
  }
}

class GarageDoorStatusSnapshot {
  const GarageDoorStatusSnapshot({
    required this.state,
    required this.lastChangedAt,
    this.shelly,
  });

  final GarageDoorState state;
  final DateTime? lastChangedAt;
  final ShellyHelperSnapshot? shelly;

  Map<String, Object?> toJson() {
    return {
      'state': state.name,
      'lastChangedAt': lastChangedAt?.toUtc().toIso8601String(),
      'shelly': shelly?.toJson(),
    };
  }
}

class ShellyHelperSnapshot {
  const ShellyHelperSnapshot({
    required this.lastCheckedAt,
    this.isReachable,
    this.relayOutput,
    this.inputState,
    this.isDoorClosedBySensor,
    this.errorMessage,
  });

  final DateTime? lastCheckedAt;
  final bool? isReachable;
  final bool? relayOutput;
  final bool? inputState;
  final bool? isDoorClosedBySensor;
  final String? errorMessage;

  Map<String, Object?> toJson() {
    return {
      'lastCheckedAt': lastCheckedAt?.toUtc().toIso8601String(),
      'isReachable': isReachable,
      'relayOutput': relayOutput,
      'inputState': inputState,
      'isDoorClosedBySensor': isDoorClosedBySensor,
      'errorMessage': errorMessage,
    };
  }
}

class ShellyStatusSnapshot {
  const ShellyStatusSnapshot({
    required this.checkedAt,
    this.relayOutput,
    this.inputState,
  });

  final DateTime checkedAt;
  final bool? relayOutput;
  final bool? inputState;
}

abstract class ShellyRelayClient {
  Future<void> triggerPulse(Duration pulseDuration);

  Future<ShellyStatusSnapshot> fetchStatus();
}

class HttpShellyRelayClient implements ShellyRelayClient {
  HttpShellyRelayClient({
    required this.baseUrl,
    required this.switchId,
    required this.inputId,
    this.timeout = const Duration(seconds: 3),
  });

  String baseUrl;
  final String switchId;
  final String inputId;
  final Duration timeout;

  void updateBaseUrl(String value) {
    baseUrl = value;
  }

  @override
  Future<ShellyStatusSnapshot> fetchStatus() async {
    final switchResponse = await _sendRequest('/rpc/Switch.GetStatus', {
      'id': switchId,
    });
    final switchDecoded = _decodeJsonObject(switchResponse.body);
    final inputResponse = await _sendRequest('/rpc/Input.GetStatus', {
      'id': inputId,
    });
    final inputDecoded = _decodeJsonObject(inputResponse.body);

    return ShellyStatusSnapshot(
      checkedAt: DateTime.now().toUtc(),
      relayOutput: _readOptionalBool(switchDecoded['output']),
      inputState: _readOptionalBool(inputDecoded['state']),
    );
  }

  @override
  Future<void> triggerPulse(Duration pulseDuration) async {
    final response = await _sendRequest('/rpc/Switch.Set', {
      'id': switchId,
      'on': 'true',
      'toggle_after': _formatDurationSeconds(pulseDuration),
    });

    if (response.statusCode != 200) {
      throw GarageDoorShellyException(
        'Shelly akzeptierte den Impuls nicht (HTTP ${response.statusCode}).',
      );
    }
  }

  Future<_HttpResponse> _sendRequest(
    String path,
    Map<String, String> queryParameters,
  ) async {
    HttpClient? client;

    try {
      final baseUri = Uri.parse(baseUrl);
      if (!GarageDoorConfig.isValidShellyBaseUrl(baseUrl)) {
        throw const FormatException('Invalid Shelly base URL');
      }
      final uri = baseUri.replace(path: path, queryParameters: queryParameters);
      client = HttpClient()..connectionTimeout = timeout;
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return _HttpResponse(statusCode: response.statusCode, body: body);
    } on TimeoutException {
      throw const GarageDoorShellyException(
        'Shelly antwortet nicht rechtzeitig.',
      );
    } on SocketException {
      throw const GarageDoorShellyException(
        'Shelly ist im Netzwerk nicht erreichbar.',
      );
    } on FormatException {
      throw const GarageDoorShellyException(
        'Shelly lieferte eine ungueltige Antwort.',
      );
    } on ArgumentError {
      throw const GarageDoorShellyException(
        'Shelly lieferte eine ungueltige Antwort.',
      );
    } finally {
      client?.close(force: true);
    }
  }

  Map<String, dynamic> _decodeJsonObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value));
    }
    throw const FormatException('Expected JSON object');
  }

  bool? _readOptionalBool(Object? value) {
    if (value is bool) {
      return value;
    }
    return null;
  }

  String _formatDurationSeconds(Duration duration) {
    final seconds = duration.inMilliseconds / 1000;
    if (seconds == seconds.roundToDouble()) {
      return seconds.toInt().toString();
    }

    return seconds.toStringAsFixed(1);
  }
}

class GarageDoorService {
  GarageDoorService({
    required GarageDoorConfig config,
    required ShellyRelayClient shellyClient,
    DateTime Function()? now,
  }) : _config = config,
       _shellyClient = shellyClient,
       _now = now ?? DateTime.now {
    _startShellyPolling();
  }

  GarageDoorConfig _config;
  final ShellyRelayClient _shellyClient;
  final DateTime Function() _now;

  GarageDoorState _state = GarageDoorState.unknown;
  DateTime? _lastChangedAt;
  Timer? _shellyPollTimer;
  DateTime? _lastShellyCheckAt;
  bool? _lastShellyReachable;
  bool? _lastRelayOutput;
  bool? _lastInputState;
  String? _lastShellyError;
  bool? _pendingTriggerPreviousInputState;
  bool _isRefreshingShellyStatus = false;

  Future<GarageDoorStatusSnapshot> getStatus() async {
    final lastCheckAt = _lastShellyCheckAt;
    final shouldRefreshNow =
        lastCheckAt == null ||
        _now().toUtc().difference(lastCheckAt) >= _config.statusRefreshDebounce;
    if (shouldRefreshNow) {
      await _pollShellyStatus(force: true);
    }

    return _buildSnapshot();
  }

  GarageDoorConfig getConfig() => _config;

  Future<GarageDoorStatusSnapshot> updateConfig(GarageDoorConfig config) async {
    _config = config;
    final shellyClient = _shellyClient;
    if (shellyClient is HttpShellyRelayClient) {
      shellyClient.updateBaseUrl(config.shellyBaseUrl);
    }
    _pendingTriggerPreviousInputState = null;
    _setState(GarageDoorState.unknown);
    await _pollShellyStatus(force: true);
    return _buildSnapshot();
  }

  Future<GarageDoorStatusSnapshot> trigger() async {
    await getStatus();

    if (_state == GarageDoorState.unknown ||
        _lastShellyReachable != true ||
        _lastInputState == null) {
      throw const GarageDoorConflictException(
        'Torstatus ist nicht bestaetigt. Impuls derzeit nicht erlaubt.',
      );
    }

    final previousInputState = _lastInputState;
    await _shellyClient.triggerPulse(_config.pulseDuration);
    _recordShellyReachable();
    _pendingTriggerPreviousInputState = previousInputState;
    _setState(GarageDoorState.unknown);

    unawaited(_pollShellyStatus(force: true));
    return _buildSnapshot();
  }

  void dispose() {
    _shellyPollTimer?.cancel();
  }

  void _startShellyPolling() {
    _shellyPollTimer?.cancel();
    _shellyPollTimer = Timer.periodic(_config.shellyPollInterval, (_) {
      unawaited(_pollShellyStatus(force: true));
    });

    unawaited(_pollShellyStatus(force: true));
  }

  Future<void> _pollShellyStatus({bool force = false}) async {
    if (_isRefreshingShellyStatus) {
      return;
    }

    final now = _now().toUtc();
    final lastCheckAt = _lastShellyCheckAt;
    if (!force &&
        lastCheckAt != null &&
        now.difference(lastCheckAt) < _config.statusRefreshDebounce) {
      return;
    }

    _isRefreshingShellyStatus = true;
    try {
      final snapshot = await _shellyClient.fetchStatus();
      _applyShellyStatusSnapshot(snapshot);
    } on GarageDoorShellyException catch (error) {
      _lastShellyCheckAt = now;
      _lastShellyReachable = false;
      _lastShellyError = error.message;
      _setState(GarageDoorState.unknown);
    } finally {
      _isRefreshingShellyStatus = false;
    }
  }

  void _applyShellyStatusSnapshot(ShellyStatusSnapshot snapshot) {
    _lastShellyCheckAt = snapshot.checkedAt.toUtc();
    _lastShellyReachable = true;
    _lastRelayOutput = snapshot.relayOutput;
    _lastInputState = snapshot.inputState;
    _lastShellyError = null;

    final inputState = snapshot.inputState;
    if (inputState == null) {
      _setState(GarageDoorState.unknown);
      return;
    }

    final pendingPreviousInputState = _pendingTriggerPreviousInputState;
    if (pendingPreviousInputState != null) {
      if (inputState == pendingPreviousInputState) {
        _setState(GarageDoorState.unknown);
        return;
      }
      _pendingTriggerPreviousInputState = null;
    }

    _setState(_stateFromInput(inputState));
  }

  GarageDoorState _stateFromInput(bool inputState) {
    return inputState ? GarageDoorState.open : GarageDoorState.closed;
  }

  void _setState(GarageDoorState state) {
    if (_state == state) {
      return;
    }

    _state = state;
    _lastChangedAt = _now().toUtc();
  }

  void _recordShellyReachable() {
    _lastShellyCheckAt = _now().toUtc();
    _lastShellyReachable = true;
    _lastShellyError = null;
  }

  GarageDoorStatusSnapshot _buildSnapshot() {
    return GarageDoorStatusSnapshot(
      state: _state,
      lastChangedAt: _lastChangedAt,
      shelly: ShellyHelperSnapshot(
        lastCheckedAt: _lastShellyCheckAt,
        isReachable: _lastShellyReachable,
        relayOutput: _lastRelayOutput,
        inputState: _lastInputState,
        isDoorClosedBySensor: _lastInputState == null
            ? null
            : _lastInputState == false,
        errorMessage: _lastShellyError,
      ),
    );
  }
}

class GarageDoorConflictException implements Exception {
  const GarageDoorConflictException(this.message);

  final String message;
}

class GarageDoorShellyException implements Exception {
  const GarageDoorShellyException(this.message);

  final String message;
}

class _HttpResponse {
  const _HttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}
