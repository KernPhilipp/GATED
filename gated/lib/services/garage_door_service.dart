import 'dart:async';
import 'dart:convert';

import '../config/app_config.dart';
import 'auth_service.dart';

enum GarageDoorState { determining, opening, open, closing, closed, unknown }

enum GarageDoorStateConfidence { modeled, heuristic, sensor }

class GarageDoorShellyStatus {
  const GarageDoorShellyStatus({
    this.lastCheckedAt,
    this.isReachable,
    this.relayOutput,
    this.inputState,
    this.isDoorClosedBySensor,
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
      inputState: json['inputState'] as bool?,
      isDoorClosedBySensor: json['isDoorClosedBySensor'] as bool?,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  final DateTime? lastCheckedAt;
  final bool? isReachable;
  final bool? relayOutput;
  final bool? inputState;
  final bool? isDoorClosedBySensor;
  final String? errorMessage;
}

class GarageDoorStatus {
  const GarageDoorStatus({
    required this.state,
    required this.stateConfidence,
    this.lastChangedAt,
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
    final lastChangedAtValue = json['lastChangedAt'];
    final lastChangedAt = lastChangedAtValue is String
        ? DateTime.tryParse(lastChangedAtValue)
        : null;
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
      lastChangedAt: lastChangedAt,
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
  final DateTime? lastChangedAt;
  final GarageDoorShellyStatus? shelly;
}

abstract class GarageDoorController {
  Future<GarageDoorStatus> fetchStatus();

  Future<GarageDoorStatus> triggerPulse();
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

  GarageDoorStatus _parseStatus(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const GarageDoorException('Ungültige Server-Antwort.');
    }

    return GarageDoorStatus.fromJson(
      decoded.map((key, value) => MapEntry('$key', value)),
    );
  }

  String _messageForStatus(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Ungültige Anfrage für den Torstatus.';
      case 401:
      case 403:
        return 'Sitzung abgelaufen. Bitte erneut anmelden.';
      case 409:
        return 'Während der Torbewegung ist derzeit kein weiterer Impuls erlaubt.';
      case 500:
        return 'Serverfehler. Bitte später versuchen.';
      case 502:
        return 'Shelly ist derzeit nicht erreichbar.';
      default:
        return 'Server-Fehler. Bitte später versuchen.';
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
    'sensor' => GarageDoorStateConfidence.sensor,
    _ => null,
  };
}
