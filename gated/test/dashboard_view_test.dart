import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gated/services/garage_door_service.dart';
import 'package:gated/views/dashboard_view.dart';

void main() {
  testWidgets('dashboard renders fetched garage door status', (tester) async {
    final controller = _FakeGarageDoorController(
      initialStatus: _status(
        state: GarageDoorState.determining,
        stateConfidence: GarageDoorStateConfidence.modeled,
        remainingMs: 4000,
        countdownLabel: 'Warten auf Sensorstatus',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DashboardView(garageDoorController: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Status wird ermittelt'), findsOneWidget);
    expect(find.text('Sensorstatus'), findsOneWidget);
    expect(find.text('Bestaetigung laeuft (4 s)'), findsOneWidget);
    expect(find.text('Impuls senden'), findsOneWidget);
    expect(find.text('Shelly-Hinweise'), findsNothing);
    expect(find.text('Hinweis zum Modell'), findsNothing);
  });

  testWidgets('dashboard sends trigger without manual correction controls', (
    tester,
  ) async {
    final controller = _FakeGarageDoorController(
      initialStatus: _status(
        state: GarageDoorState.closed,
        stateConfidence: GarageDoorStateConfidence.modeled,
      ),
      triggerStatus: _status(
        state: GarageDoorState.opening,
        stateConfidence: GarageDoorStateConfidence.modeled,
        remainingMs: 5000,
        countdownLabel: 'Warten auf Sensorbestaetigung offen',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DashboardView(garageDoorController: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('Impuls senden'));
    await tester.tap(find.text('Impuls senden'));
    await tester.pump();

    expect(controller.triggerCalls, 1);
    expect(find.text('Tor oeffnet'), findsOneWidget);
    expect(find.text('Status manuell korrigieren'), findsNothing);
    expect(find.text('Als unbekannt markieren'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dashboard displays Shelly sensor state', (tester) async {
    final controller = _FakeGarageDoorController(
      initialStatus: _status(
        state: GarageDoorState.closed,
        stateConfidence: GarageDoorStateConfidence.sensor,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DashboardView(garageDoorController: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Sensorstatus'), findsOneWidget);
    expect(find.text('Erreichbar'), findsWidgets);
    expect(find.text('Shelly'), findsOneWidget);
    expect(find.text('Relais'), findsNothing);
    expect(find.text('Sensor zuletzt geprueft'), findsOneWidget);
    expect(find.text('Letzte Aenderung'), findsOneWidget);
  });

  testWidgets('dashboard hides removed technical detail rows', (tester) async {
    final controller = _FakeGarageDoorController(
      initialStatus: _status(
        state: GarageDoorState.unknown,
        stateConfidence: GarageDoorStateConfidence.heuristic,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DashboardView(garageDoorController: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Statusbasis'), findsNothing);
    expect(find.text('Naechster modellierter Zustand'), findsNothing);
    expect(find.text('Letzte Aktion'), findsNothing);
    expect(find.text('Relais'), findsNothing);
  });

  testWidgets('dashboard disables trigger while Shelly sensor is unavailable', (
    tester,
  ) async {
    final controller = _FakeGarageDoorController(
      initialStatus: _status(
        state: GarageDoorState.closed,
        stateConfidence: GarageDoorStateConfidence.sensor,
        shelly: const GarageDoorShellyStatus(
          isReachable: false,
          errorMessage: 'Shelly antwortet nicht rechtzeitig.',
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DashboardView(garageDoorController: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Nicht erreichbar'), findsOneWidget);
    expect(find.text('Shelly antwortet nicht rechtzeitig.'), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Impuls senden'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('dashboard keeps last known status during backend outages', (
    tester,
  ) async {
    final controller = _SequenceGarageDoorController(
      fetchResults: [
        _status(
          state: GarageDoorState.closed,
          stateConfidence: GarageDoorStateConfidence.modeled,
        ),
        const GarageDoorException('Backend offline.'),
        _status(
          state: GarageDoorState.open,
          stateConfidence: GarageDoorStateConfidence.modeled,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DashboardView(garageDoorController: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Tor geschlossen'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Tor geschlossen'), findsOneWidget);
    expect(find.text('Backend derzeit nicht erreichbar'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Tor offen'), findsOneWidget);
    expect(find.text('Backend derzeit nicht erreichbar'), findsNothing);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FakeGarageDoorController implements GarageDoorController {
  _FakeGarageDoorController({
    required this.initialStatus,
    GarageDoorStatus? triggerStatus,
  }) : _triggerStatus = triggerStatus ?? initialStatus;

  final GarageDoorStatus initialStatus;
  final GarageDoorStatus _triggerStatus;
  int triggerCalls = 0;

  @override
  Future<GarageDoorStatus> fetchStatus() async => initialStatus;

  @override
  Future<GarageDoorStatus> triggerPulse() async {
    triggerCalls++;
    return _triggerStatus;
  }
}

class _SequenceGarageDoorController implements GarageDoorController {
  _SequenceGarageDoorController({required List<Object> fetchResults})
    : _fetchResults = List<Object>.from(fetchResults),
      _lastResult = fetchResults.last;

  final List<Object> _fetchResults;
  final Object _lastResult;

  @override
  Future<GarageDoorStatus> fetchStatus() async {
    final next = _fetchResults.isEmpty
        ? _lastResult
        : _fetchResults.removeAt(0);
    if (next is GarageDoorStatus) {
      return next;
    }

    throw next as Exception;
  }

  @override
  Future<GarageDoorStatus> triggerPulse() async {
    throw UnimplementedError();
  }
}

GarageDoorStatus _status({
  required GarageDoorState state,
  required GarageDoorStateConfidence stateConfidence,
  int? remainingMs,
  String? countdownLabel,
  GarageDoorShellyStatus shelly = const GarageDoorShellyStatus(
    isReachable: true,
    relayOutput: false,
    inputState: false,
    isDoorClosedBySensor: true,
  ),
}) {
  return GarageDoorStatus(
    state: state,
    stateConfidence: stateConfidence,
    nextState: null,
    phaseEndsAt: null,
    remainingMs: remainingMs,
    countdownLabel: countdownLabel,
    lastChangedAt: DateTime.utc(2026, 4, 19, 12),
    shelly: shelly,
  );
}
