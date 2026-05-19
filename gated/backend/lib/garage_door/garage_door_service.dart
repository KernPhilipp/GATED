import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';

import '../db/database.dart';

enum GarageDoorState { determining, opening, open, closing, closed, unknown }

enum GarageDoorStateConfidence { modeled, heuristic, sensor }

class GarageDoorConfig {
  const GarageDoorConfig({
    required this.shellyBaseUrl,
    required this.switchId,
    required this.inputId,
    required this.sensorSettleDuration,
    required this.shellyRequestTimeout,
    required this.statusRefreshDebounce,
    required this.shellyPollInterval,
    required this.selfTriggerSuppressionWindow,
    required this.pulseDuration,
    required this.openingDuration,
    required this.openHoldDuration,
    required this.closingDuration,
    required this.startupDeterminationDuration,
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
      inputId: '0',
      sensorSettleDuration: const Duration(seconds: 5),
      shellyRequestTimeout: Duration(
        seconds: readSeconds('SHELLY_REQUEST_TIMEOUT_SECONDS', 3),
      ),
      statusRefreshDebounce: Duration(
        seconds: readSeconds('GARAGE_DOOR_STATUS_REFRESH_SECONDS', 2),
      ),
      shellyPollInterval: Duration(
        milliseconds: readMilliseconds('GARAGE_DOOR_SHELLY_POLL_MS', 250),
      ),
      selfTriggerSuppressionWindow: Duration(
        milliseconds: readMilliseconds(
          'GARAGE_DOOR_SELF_TRIGGER_SUPPRESSION_MS',
          1500,
        ),
      ),
      pulseDuration: Duration(
        seconds: readSeconds('GARAGE_DOOR_PULSE_SECONDS', 1),
      ),
      openingDuration: Duration(
        seconds: readSeconds('GARAGE_DOOR_OPENING_SECONDS', 5),
      ),
      openHoldDuration: Duration(
        seconds: readSeconds('GARAGE_DOOR_OPEN_HOLD_SECONDS', 5),
      ),
      closingDuration: Duration(
        seconds: readSeconds('GARAGE_DOOR_CLOSING_SECONDS', 5),
      ),
      startupDeterminationDuration: Duration(
        seconds: readSeconds('GARAGE_DOOR_STARTUP_SECONDS', 5),
      ),
    );
  }

  final String shellyBaseUrl;
  final String switchId;
  final String inputId;
  final Duration sensorSettleDuration;
  final Duration shellyRequestTimeout;
  final Duration statusRefreshDebounce;
  final Duration shellyPollInterval;
  final Duration selfTriggerSuppressionWindow;
  final Duration pulseDuration;
  final Duration openingDuration;
  final Duration openHoldDuration;
  final Duration closingDuration;
  final Duration startupDeterminationDuration;

  GarageDoorConfig copyWith({String? shellyBaseUrl}) {
    return GarageDoorConfig(
      shellyBaseUrl: shellyBaseUrl ?? this.shellyBaseUrl,
      switchId: switchId,
      inputId: inputId,
      sensorSettleDuration: sensorSettleDuration,
      shellyRequestTimeout: shellyRequestTimeout,
      statusRefreshDebounce: statusRefreshDebounce,
      shellyPollInterval: shellyPollInterval,
      selfTriggerSuppressionWindow: selfTriggerSuppressionWindow,
      pulseDuration: pulseDuration,
      openingDuration: openingDuration,
      openHoldDuration: openHoldDuration,
      closingDuration: closingDuration,
      startupDeterminationDuration: startupDeterminationDuration,
    );
  }

  GarageDoorConfig withRuntimeConfig(DbGarageDoorConfig config) {
    return copyWith(shellyBaseUrl: config.shellyBaseUrl);
  }

  DbGarageDoorConfig toDbConfig() {
    return DbGarageDoorConfig(shellyBaseUrl: shellyBaseUrl);
  }

  Map<String, Object?> toPublicJson() {
    return {'shellyBaseUrl': shellyBaseUrl};
  }
}

class GarageDoorStatusSnapshot {
  const GarageDoorStatusSnapshot({
    required this.state,
    required this.stateConfidence,
    required this.lastChangedAt,
    this.nextState,
    this.phaseEndsAt,
    this.remainingMs,
    this.countdownLabel,
    this.shelly,
  });

  final GarageDoorState state;
  final GarageDoorStateConfidence stateConfidence;
  final GarageDoorState? nextState;
  final DateTime? phaseEndsAt;
  final int? remainingMs;
  final String? countdownLabel;
  final DateTime? lastChangedAt;
  final ShellyHelperSnapshot? shelly;

  Map<String, Object?> toJson() {
    return {
      'state': state.name,
      'stateConfidence': stateConfidence.name,
      'nextState': nextState?.name,
      'phaseEndsAt': phaseEndsAt?.toUtc().toIso8601String(),
      'remainingMs': remainingMs,
      'countdownLabel': countdownLabel,
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
    final baseUri = Uri.parse(baseUrl);
    final uri = baseUri.replace(path: path, queryParameters: queryParameters);
    final client = HttpClient()..connectionTimeout = timeout;

    try {
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
    } finally {
      client.close(force: true);
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
    _startDetermining();
    _startShellyPolling();
  }

  GarageDoorConfig _config;
  final ShellyRelayClient _shellyClient;
  final DateTime Function() _now;

  GarageDoorState _state = GarageDoorState.unknown;
  GarageDoorStateConfidence _stateConfidence =
      GarageDoorStateConfidence.modeled;
  GarageDoorState? _nextState;
  String? _countdownLabel;
  DateTime? _phaseEndsAt;
  DateTime? _lastChangedAt;
  Timer? _phaseTimer;
  Timer? _shellyPollTimer;
  DateTime? _lastShellyCheckAt;
  DateTime? _lastInternalTriggerAt;
  bool? _lastObservedRelayOutput;
  bool? _lastShellyReachable;
  bool? _lastRelayOutput;
  bool? _lastInputState;
  String? _lastShellyError;
  bool _isSensorSettlePhase = false;
  bool _isRefreshingShellyStatus = false;

  Future<GarageDoorStatusSnapshot> getStatus() async {
    _syncState();

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
    await _pollShellyStatus(force: true);
    return _buildSnapshot();
  }

  Future<GarageDoorStatusSnapshot> trigger() async {
    _syncState();

    if (_state == GarageDoorState.opening ||
        _state == GarageDoorState.closing) {
      throw const GarageDoorConflictException(
        'Waehren der Bewegung ist kein weiterer Impuls erlaubt.',
      );
    }

    await _shellyClient.triggerPulse(_config.pulseDuration);
    _recordShellyReachable();
    _lastInternalTriggerAt = _now().toUtc();

    if (_state == GarageDoorState.open) {
      _startClosing(stateConfidence: GarageDoorStateConfidence.modeled);
    } else {
      _startOpening(stateConfidence: GarageDoorStateConfidence.modeled);
    }

    unawaited(_pollShellyStatus(force: true));
    return _buildSnapshot();
  }

  void dispose() {
    _phaseTimer?.cancel();
    _shellyPollTimer?.cancel();
  }

  void _startDetermining() {
    _setMovingState(
      GarageDoorState.determining,
      nextState: null,
      countdownLabel: 'Warten auf Sensorstatus',
      stateConfidence: GarageDoorStateConfidence.modeled,
    );
  }

  void _startOpening({GarageDoorStateConfidence? stateConfidence}) {
    _setMovingState(
      GarageDoorState.opening,
      nextState: GarageDoorState.open,
      countdownLabel: 'Warten auf Sensorbestaetigung offen',
      stateConfidence: stateConfidence,
    );
  }

  void _startOpenHold({GarageDoorStateConfidence? stateConfidence}) {
    _setTimedState(
      GarageDoorState.open,
      duration: _config.openHoldDuration,
      nextState: GarageDoorState.closing,
      countdownLabel: 'Bis automatisches Schliessen',
      stateConfidence: stateConfidence,
    );
  }

  void _startClosing({GarageDoorStateConfidence? stateConfidence}) {
    _setMovingState(
      GarageDoorState.closing,
      nextState: GarageDoorState.closed,
      countdownLabel: 'Warten auf Sensorbestaetigung geschlossen',
      stateConfidence: stateConfidence,
    );
  }

  void _setMovingState(
    GarageDoorState state, {
    required GarageDoorState? nextState,
    required String countdownLabel,
    GarageDoorStateConfidence? stateConfidence,
  }) {
    _phaseTimer?.cancel();
    _phaseTimer = null;
    _state = state;
    _nextState = nextState;
    _countdownLabel = countdownLabel;
    _phaseEndsAt = null;
    _isSensorSettlePhase = false;
    _lastChangedAt = _now().toUtc();
    if (stateConfidence != null) {
      _stateConfidence = stateConfidence;
    }
  }

  void _setStableState(
    GarageDoorState state, {
    GarageDoorStateConfidence? stateConfidence,
  }) {
    _phaseTimer?.cancel();
    _phaseTimer = null;
    _state = state;
    _nextState = null;
    _countdownLabel = null;
    _phaseEndsAt = null;
    _isSensorSettlePhase = false;
    _lastChangedAt = _now().toUtc();
    if (stateConfidence != null) {
      _stateConfidence = stateConfidence;
    }
  }

  void _setTimedState(
    GarageDoorState state, {
    required Duration duration,
    required GarageDoorState nextState,
    required String countdownLabel,
    GarageDoorStateConfidence? stateConfidence,
    bool isSensorSettlePhase = false,
  }) {
    _phaseTimer?.cancel();
    _phaseTimer = null;

    _state = state;
    _nextState = nextState;
    _countdownLabel = countdownLabel;
    _phaseEndsAt = _now().toUtc().add(duration);
    _isSensorSettlePhase = isSensorSettlePhase;
    _lastChangedAt = _now().toUtc();
    if (stateConfidence != null) {
      _stateConfidence = stateConfidence;
    }
    _phaseTimer = Timer(duration, _completeCurrentPhase);
  }

  void _syncState() {
    var safetyCounter = 0;
    while (_phaseEndsAt != null &&
        !_now().toUtc().isBefore(_phaseEndsAt!) &&
        safetyCounter < 8) {
      _completeCurrentPhase();
      safetyCounter++;
    }
  }

  void _completeCurrentPhase() {
    _phaseTimer?.cancel();
    _phaseTimer = null;

    if (_isSensorSettlePhase && _nextState != null) {
      final completedState = _nextState!;
      _setStableState(
        completedState,
        stateConfidence: GarageDoorStateConfidence.sensor,
      );
      return;
    }

    switch (_state) {
      case GarageDoorState.determining:
        _setStableState(
          GarageDoorState.closed,
          stateConfidence: GarageDoorStateConfidence.modeled,
        );
        break;
      case GarageDoorState.opening:
        _startOpenHold();
        break;
      case GarageDoorState.open:
        _startClosing();
        break;
      case GarageDoorState.closing:
        _setStableState(GarageDoorState.closed);
        break;
      case GarageDoorState.closed:
      case GarageDoorState.unknown:
        break;
    }
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
    if (inputState != null) {
      _applySensorState(inputState);
      _lastObservedRelayOutput = snapshot.relayOutput;
      return;
    }

    final currentOutput = snapshot.relayOutput;
    final previousOutput = _lastObservedRelayOutput;

    if (currentOutput != null) {
      final isRisingEdge = previousOutput == false && currentOutput == true;
      if (isRisingEdge &&
          !_isSuppressedSelfTrigger(snapshot.checkedAt.toUtc())) {
        _handleExternalHeuristicTrigger();
      }

      _lastObservedRelayOutput = currentOutput;
    }
  }

  void _applySensorState(bool inputState) {
    _syncState();

    final isClosedBySensor = inputState == false;
    switch (_state) {
      case GarageDoorState.determining:
        _startSensorSettle(
          isClosedBySensor ? GarageDoorState.closed : GarageDoorState.open,
        );
        break;
      case GarageDoorState.closed:
      case GarageDoorState.unknown:
        if (!isClosedBySensor) {
          _startSensorSettle(GarageDoorState.open);
        }
        break;
      case GarageDoorState.open:
        if (isClosedBySensor) {
          _startSensorSettle(GarageDoorState.closed);
        }
        break;
      case GarageDoorState.opening:
        if (!isClosedBySensor) {
          _startSensorSettle(GarageDoorState.open);
        }
        break;
      case GarageDoorState.closing:
        if (isClosedBySensor) {
          _startSensorSettle(GarageDoorState.closed);
        }
        break;
    }
  }

  void _startSensorSettle(GarageDoorState targetState) {
    if (_isSensorSettlePhase &&
        _nextState == targetState &&
        _phaseEndsAt != null) {
      return;
    }

    final movingState = targetState == GarageDoorState.closed
        ? GarageDoorState.closing
        : GarageDoorState.opening;

    _setTimedState(
      movingState,
      duration: _config.sensorSettleDuration,
      nextState: targetState,
      countdownLabel: targetState == GarageDoorState.closed
          ? 'Bis Sensorstatus geschlossen bestaetigt'
          : 'Bis Sensorstatus offen bestaetigt',
      stateConfidence: GarageDoorStateConfidence.sensor,
      isSensorSettlePhase: true,
    );
  }

  bool _isSuppressedSelfTrigger(DateTime detectedAt) {
    final lastInternalTriggerAt = _lastInternalTriggerAt;
    if (lastInternalTriggerAt == null ||
        detectedAt.isBefore(lastInternalTriggerAt)) {
      return false;
    }

    return detectedAt.difference(lastInternalTriggerAt) <=
        _config.selfTriggerSuppressionWindow;
  }

  void _handleExternalHeuristicTrigger() {
    _syncState();

    switch (_state) {
      case GarageDoorState.closed:
      case GarageDoorState.unknown:
      case GarageDoorState.determining:
        _startOpening(stateConfidence: GarageDoorStateConfidence.heuristic);
        break;
      case GarageDoorState.open:
        _startClosing(stateConfidence: GarageDoorStateConfidence.heuristic);
        break;
      case GarageDoorState.opening:
      case GarageDoorState.closing:
        _setStableState(
          GarageDoorState.unknown,
          stateConfidence: GarageDoorStateConfidence.heuristic,
        );
        break;
    }
  }

  void _recordShellyReachable() {
    _lastShellyCheckAt = _now().toUtc();
    _lastShellyReachable = true;
    _lastShellyError = null;
  }

  GarageDoorStatusSnapshot _buildSnapshot() {
    final phaseEndsAt = _phaseEndsAt;
    final remainingMs = phaseEndsAt == null
        ? null
        : phaseEndsAt
              .difference(_now().toUtc())
              .inMilliseconds
              .clamp(0, 1 << 31);

    return GarageDoorStatusSnapshot(
      state: _state,
      stateConfidence: _stateConfidence,
      nextState: _nextState,
      phaseEndsAt: phaseEndsAt,
      remainingMs: phaseEndsAt == null ? null : remainingMs as int,
      countdownLabel: _countdownLabel,
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
