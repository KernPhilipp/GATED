import 'dart:async';
import 'dart:convert';

import '../config/app_config.dart';
import 'auth_service.dart';

enum GarageDoorState { determining, opening, open, closing, closed, unknown }

enum GarageDoorStateConfidence { modeled, heuristic }

class GarageDoorLastAction {
  const GarageDoorLastAction({
    required this.type,
    required this.source,
    required this.description,
    required this.timestamp,
  });

  factory GarageDoorLastAction.fromJson(Map<String, dynamic> json) {
    final timestampValue = json['timestamp'];
    final timestamp = timestampValue is String
        ? DateTime.tryParse(timestampValue)
        : null;

    return GarageDoorLastAction(
      type: json['type'] as String? ?? 'unknown',
      source: json['source'] as String? ?? 'unknown',
      description: json['description'] as String? ?? '',
      timestamp: timestamp,
    );
  }

  final String type;
  final String source;
  final String description;
  final DateTime? timestamp;
}

class GarageDoorShellyStatus {
  const GarageDoorShellyStatus({
    this.lastCheckedAt,
    this.isReachable,
    this.relayOutput,
    this.errorMessage,
  });

  factory GarageDoorShellyStatus.fromJson(Map<String, dynamic> json) {
    final checkedAtValue = json['lastCheckedAt'];
    final checkedAt = checkedAtValue is String
        ? DateTime.tryParse(checkedAtValue)
        : null;

    return GarageDoorShellyStatus(
      lastCheckedAt: checkedAt,
      isReachable: json['isReachable'] as bool?,
      relayOutput: json['relayOutput'] as bool?,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  final DateTime? lastCheckedAt;
  final bool? isReachable;
  final bool? relayOutput;
  final String? errorMessage;
}

class GarageDoorStatus {
  const GarageDoorStatus({
    required this.state,
    required this.stateConfidence,
    required this.lastAction,
    this.nextState,
    this.phaseEndsAt,
    this.remainingMs,
    this.countdownLabel,
    this.shelly,
  });

  factory GarageDoorStatus.fromJson(Map<String, dynamic> json) {
    final stateName = json['state'] as String?;
    final confidenceName = json['stateConfidence'] as String?;
    final nextStateName = json['nextState'] as String?;
    final phaseEndsAtValue = json['phaseEndsAt'];
    final phaseEndsAt = phaseEndsAtValue is String
        ? DateTime.tryParse(phaseEndsAtValue)
        : null;
    final lastActionJson = json['lastAction'];
    final shellyJson = json['shelly'];

    return GarageDoorStatus(
      state: _stateFromName(stateName) ?? GarageDoorState.unknown,
      stateConfidence:
          _confidenceFromName(confidenceName) ??
          GarageDoorStateConfidence.modeled,
      nextState: _stateFromName(nextStateName),
      phaseEndsAt: phaseEndsAt,
      remainingMs: json['remainingMs'] as int?,
      countdownLabel: json['countdownLabel'] as String?,
      lastAction: lastActionJson is Map
          ? GarageDoorLastAction.fromJson(
              lastActionJson.map((key, value) => MapEntry('$key', value)),
            )
          : const GarageDoorLastAction(
              type: 'unknown',
              source: 'unknown',
              description: '',
              timestamp: null,
            ),
      shelly: shellyJson is Map
          ? GarageDoorShellyStatus.fromJson(
              shellyJson.map((key, value) => MapEntry('$key', value)),
            )
          : null,
    );
  }

  final GarageDoorState state;
  final GarageDoorStateConfidence stateConfidence;
  final GarageDoorState? nextState;
  final DateTime? phaseEndsAt;
  final int? remainingMs;
  final String? countdownLabel;
  final GarageDoorLastAction lastAction;
  final GarageDoorShellyStatus? shelly;
}

abstract class GarageDoorController {
  Future<GarageDoorStatus> fetchStatus();

  Future<GarageDoorStatus> triggerPulse();

  Future<GarageDoorStatus> setManualState(GarageDoorState state);
}

class GarageDoorService implements GarageDoorController {
  GarageDoorService({
    String baseUrl = AppConfig.apiBaseUrl,
    AuthService? authService,
  }) : _authService = authService ?? AuthService(baseUrl: baseUrl);

  final AuthService _authService;

  @override
  Future<GarageDoorStatus> fetchStatus() async {
    final response = await _authService
        .sendAuthorizedRequest(method: 'GET', path: '/garage-door/status')
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw GarageDoorException(_messageForStatus(response.statusCode));
    }

    return _parseStatus(response.body);
  }

  @override
  Future<GarageDoorStatus> triggerPulse() async {
    final response = await _authService
        .sendAuthorizedRequest(method: 'POST', path: '/garage-door/trigger')
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw GarageDoorException(_messageForStatus(response.statusCode));
    }

    return _parseStatus(response.body);
  }

  @override
  Future<GarageDoorStatus> setManualState(GarageDoorState state) async {
    final response = await _authService
        .sendAuthorizedRequest(
          method: 'POST',
          path: '/garage-door/state',
          includeJsonContentType: true,
          body: jsonEncode({'state': state.name}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw GarageDoorException(_messageForStatus(response.statusCode));
    }

    return _parseStatus(response.body);
  }

  GarageDoorStatus _parseStatus(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const GarageDoorException('Ungueltige Server-Antwort.');
    }

    return GarageDoorStatus.fromJson(
      decoded.map((key, value) => MapEntry('$key', value)),
    );
  }

  String _messageForStatus(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Ungueltige Anfrage fuer den Torstatus.';
      case 401:
      case 403:
        return 'Sitzung abgelaufen. Bitte erneut anmelden.';
      case 409:
        return 'Waehren der Torbewegung ist derzeit kein weiterer Impuls erlaubt.';
      case 500:
        return 'Serverfehler. Bitte spaeter versuchen.';
      case 502:
        return 'Shelly ist derzeit nicht erreichbar.';
      default:
        return 'Server-Fehler. Bitte spaeter versuchen.';
    }
  }
}

class GarageDoorException implements Exception {
  const GarageDoorException(this.message);

  final String message;
}

GarageDoorState? _stateFromName(String? name) {
  return switch (name) {
    'determining' => GarageDoorState.determining,
    'opening' => GarageDoorState.opening,
    'open' => GarageDoorState.open,
    'closing' => GarageDoorState.closing,
    'closed' => GarageDoorState.closed,
    'unknown' => GarageDoorState.unknown,
    _ => null,
  };
}

GarageDoorStateConfidence? _confidenceFromName(String? name) {
  return switch (name) {
    'modeled' => GarageDoorStateConfidence.modeled,
    'heuristic' => GarageDoorStateConfidence.heuristic,
    _ => null,
  };
}
