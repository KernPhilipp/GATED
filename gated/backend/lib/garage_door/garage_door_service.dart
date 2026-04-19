import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';

enum GarageDoorState { determining, opening, open, closing, closed, unknown }

enum GarageDoorActionType {
  startup,
  trigger,
  manualOverride,
  automaticTransition,
  externalHeuristicTrigger,
}

enum GarageDoorStateConfidence { modeled, heuristic }

class GarageDoorConfig {
  const GarageDoorConfig({
    required this.shellyBaseUrl,
    required this.switchId,
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
  final Duration shellyRequestTimeout;
  final Duration statusRefreshDebounce;
  final Duration shellyPollInterval;
  final Duration selfTriggerSuppressionWindow;
  final Duration pulseDuration;
  final Duration openingDuration;
  final Duration openHoldDuration;
  final Duration closingDuration;
  final Duration startupDeterminationDuration;
}

class GarageDoorStatusSnapshot {
  const GarageDoorStatusSnapshot({
    required this.state,
    required this.stateConfidence,
    required this.lastAction,
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
  final GarageDoorLastAction lastAction;
  final ShellyHelperSnapshot? shelly;

  Map<String, Object?> toJson() {
    return {
      'state': state.name,
      'stateConfidence': stateConfidence.name,
      'nextState': nextState?.name,
      'phaseEndsAt': phaseEndsAt?.toUtc().toIso8601String(),
      'remainingMs': remainingMs,
      'countdownLabel': countdownLabel,
      'lastAction': lastAction.toJson(),
      'shelly': shelly?.toJson(),
    };
  }
}

class GarageDoorLastAction {
  const GarageDoorLastAction({
    required this.type,
    required this.source,
    required this.description,
    required this.timestamp,
  });

  final GarageDoorActionType type;
  final String source;
  final String description;
  final DateTime timestamp;

  Map<String, Object?> toJson() {
    return {
      'type': type.name,
      'source': source,
      'description': description,
      'timestamp': timestamp.toUtc().toIso8601String(),
    };
  }
}

class ShellyHelperSnapshot {
  const ShellyHelperSnapshot({
    required this.lastCheckedAt,
    this.isReachable,
    this.relayOutput,
    this.errorMessage,
  });

  final DateTime? lastCheckedAt;
  final bool? isReachable;
  final bool? relayOutput;
  final String? errorMessage;

  Map<String, Object?> toJson() {
    return {
      'lastCheckedAt': lastCheckedAt?.toUtc().toIso8601String(),
      'isReachable': isReachable,
      'relayOutput': relayOutput,
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
    this.timeout = const Duration(seconds: 3),
  });

  final String baseUrl;
  final String switchId;
  final Duration timeout;

  @override
  Future<ShellyStatusSnapshot> fetchStatus() async {
    final response = await _sendRequest('/rpc/Switch.GetStatus', {
      'id': switchId,
    });
    final decoded = _decodeJsonObject(response.body);

    return ShellyStatusSnapshot(
      checkedAt: DateTime.now().toUtc(),
      relayOutput: _readOptionalBool(decoded['output']),
      inputState: _readOptionalBool(decoded['input']),
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

  final GarageDoorConfig _config;
  final ShellyRelayClient _shellyClient;
  final DateTime Function() _now;

  GarageDoorState _state = GarageDoorState.unknown;
  GarageDoorStateConfidence _stateConfidence =
      GarageDoorStateConfidence.modeled;
  GarageDoorState? _nextState;
  String? _countdownLabel;
  DateTime? _phaseEndsAt;
  Timer? _phaseTimer;
  Timer? _shellyPollTimer;
  DateTime? _lastShellyCheckAt;
  DateTime? _lastInternalTriggerAt;
  bool? _lastObservedRelayOutput;
  bool? _lastShellyReachable;
  bool? _lastRelayOutput;
  String? _lastShellyError;
  GarageDoorLastAction _lastAction = GarageDoorLastAction(
    type: GarageDoorActionType.startup,
    source: 'backend',
    description: 'Initialisierung gestartet.',
    timestamp: DateTime.now().toUtc(),
  );
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
      _startClosing(
        action: _createAction(
          type: GarageDoorActionType.trigger,
          source: 'dashboard',
          description: 'Manueller Impuls zum vorzeitigen Schliessen gesendet.',
        ),
        stateConfidence: GarageDoorStateConfidence.modeled,
      );
    } else {
      _startOpening(
        action: _createAction(
          type: GarageDoorActionType.trigger,
          source: 'dashboard',
          description: 'Manueller Impuls zum Oeffnen gesendet.',
        ),
        stateConfidence: GarageDoorStateConfidence.modeled,
      );
    }

    unawaited(_pollShellyStatus(force: true));
    return _buildSnapshot();
  }

  GarageDoorStatusSnapshot setManualState(GarageDoorState state) {
    _syncState();

    final action = _createAction(
      type: GarageDoorActionType.manualOverride,
      source: 'dashboard',
      description: 'Torstatus manuell auf ${state.name} gesetzt.',
    );

    switch (state) {
      case GarageDoorState.open:
        _startOpenHold(
          action: action,
          stateConfidence: GarageDoorStateConfidence.modeled,
        );
        break;
      case GarageDoorState.closed:
        _setStableState(
          GarageDoorState.closed,
          action: action,
          stateConfidence: GarageDoorStateConfidence.modeled,
        );
        break;
      case GarageDoorState.unknown:
        _setStableState(
          GarageDoorState.unknown,
          action: action,
          stateConfidence: GarageDoorStateConfidence.modeled,
        );
        break;
      case GarageDoorState.determining:
      case GarageDoorState.opening:
      case GarageDoorState.closing:
        throw const GarageDoorConflictException(
          'Dieser Status darf nicht manuell gesetzt werden.',
        );
    }

    return _buildSnapshot();
  }

  void dispose() {
    _phaseTimer?.cancel();
    _shellyPollTimer?.cancel();
  }

  void _startDetermining() {
    _setTimedState(
      GarageDoorState.determining,
      duration: _config.startupDeterminationDuration,
      nextState: GarageDoorState.closed,
      countdownLabel: 'Bis Standardstatus geschlossen',
      action: _createAction(
        type: GarageDoorActionType.startup,
        source: 'backend',
        description: 'Status wird nach Backend-Start ermittelt.',
      ),
      stateConfidence: GarageDoorStateConfidence.modeled,
    );
  }

  void _startOpening({
    required GarageDoorLastAction action,
    GarageDoorStateConfidence? stateConfidence,
  }) {
    _setTimedState(
      GarageDoorState.opening,
      duration: _config.openingDuration,
      nextState: GarageDoorState.open,
      countdownLabel: 'Bis Zustand offen',
      action: action,
      stateConfidence: stateConfidence,
    );
  }

  void _startOpenHold({
    required GarageDoorLastAction action,
    GarageDoorStateConfidence? stateConfidence,
  }) {
    _setTimedState(
      GarageDoorState.open,
      duration: _config.openHoldDuration,
      nextState: GarageDoorState.closing,
      countdownLabel: 'Bis automatisches Schliessen',
      action: action,
      stateConfidence: stateConfidence,
    );
  }

  void _startClosing({
    required GarageDoorLastAction action,
    GarageDoorStateConfidence? stateConfidence,
  }) {
    _setTimedState(
      GarageDoorState.closing,
      duration: _config.closingDuration,
      nextState: GarageDoorState.closed,
      countdownLabel: 'Bis Zustand geschlossen',
      action: action,
      stateConfidence: stateConfidence,
    );
  }

  void _setStableState(
    GarageDoorState state, {
    required GarageDoorLastAction action,
    GarageDoorStateConfidence? stateConfidence,
  }) {
    _phaseTimer?.cancel();
    _phaseTimer = null;
    _state = state;
    _nextState = null;
    _countdownLabel = null;
    _phaseEndsAt = null;
    _lastAction = action;
    if (stateConfidence != null) {
      _stateConfidence = stateConfidence;
    }
  }

  void _setTimedState(
    GarageDoorState state, {
    required Duration duration,
    required GarageDoorState nextState,
    required String countdownLabel,
    required GarageDoorLastAction action,
    GarageDoorStateConfidence? stateConfidence,
  }) {
    _phaseTimer?.cancel();
    _phaseTimer = null;

    _state = state;
    _nextState = nextState;
    _countdownLabel = countdownLabel;
    _phaseEndsAt = _now().toUtc().add(duration);
    _lastAction = action;
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

    switch (_state) {
      case GarageDoorState.determining:
        _setStableState(
          GarageDoorState.closed,
          action: _createAction(
            type: GarageDoorActionType.automaticTransition,
            source: 'backend',
            description:
                'Initiale Ermittlung abgeschlossen, Standardstatus geschlossen.',
          ),
          stateConfidence: GarageDoorStateConfidence.modeled,
        );
        break;
      case GarageDoorState.opening:
        _startOpenHold(
          action: _createAction(
            type: GarageDoorActionType.automaticTransition,
            source: 'backend',
            description: 'Modellierter Zustand auf offen gewechselt.',
          ),
        );
        break;
      case GarageDoorState.open:
        _startClosing(
          action: _createAction(
            type: GarageDoorActionType.automaticTransition,
            source: 'backend',
            description: 'Automatisches Schliessen gestartet.',
          ),
        );
        break;
      case GarageDoorState.closing:
        _setStableState(
          GarageDoorState.closed,
          action: _createAction(
            type: GarageDoorActionType.automaticTransition,
            source: 'backend',
            description: 'Modellierter Zustand auf geschlossen gewechselt.',
          ),
        );
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
    _lastShellyError = null;

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
        _startOpening(
          action: _createAction(
            type: GarageDoorActionType.externalHeuristicTrigger,
            source: 'heuristic-external',
            description:
                'Heuristisch externer Shelly-Impuls erkannt. Modell startet Oeffnung.',
          ),
          stateConfidence: GarageDoorStateConfidence.heuristic,
        );
        break;
      case GarageDoorState.open:
        _startClosing(
          action: _createAction(
            type: GarageDoorActionType.externalHeuristicTrigger,
            source: 'heuristic-external',
            description:
                'Heuristisch externer Shelly-Impuls erkannt. Modell startet Schliessen.',
          ),
          stateConfidence: GarageDoorStateConfidence.heuristic,
        );
        break;
      case GarageDoorState.opening:
      case GarageDoorState.closing:
        _setStableState(
          GarageDoorState.unknown,
          action: _createAction(
            type: GarageDoorActionType.externalHeuristicTrigger,
            source: 'heuristic-external',
            description:
                'Heuristisch externer Shelly-Impuls waehrend laufender Bewegung erkannt. Status auf unbekannt gesetzt.',
          ),
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

  GarageDoorLastAction _createAction({
    required GarageDoorActionType type,
    required String source,
    required String description,
  }) {
    return GarageDoorLastAction(
      type: type,
      source: source,
      description: description,
      timestamp: _now().toUtc(),
    );
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
      lastAction: _lastAction,
      shelly: ShellyHelperSnapshot(
        lastCheckedAt: _lastShellyCheckAt,
        isReachable: _lastShellyReachable,
        relayOutput: _lastRelayOutput,
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
