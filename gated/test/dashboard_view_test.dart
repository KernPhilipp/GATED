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
        countdownLabel: 'Bis Standardstatus geschlossen',
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
    expect(find.text('Bis Standardstatus geschlossen'), findsOneWidget);
    expect(find.text('Impuls senden'), findsOneWidget);
  });

  testWidgets('dashboard sends trigger and manual correction actions', (
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
        countdownLabel: 'Bis Zustand offen',
      ),
      manualStatus: _status(
        state: GarageDoorState.unknown,
        stateConfidence: GarageDoorStateConfidence.modeled,
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

    await tester.ensureVisible(find.text('Als unbekannt markieren'));
    await tester.tap(find.text('Als unbekannt markieren'));
    await tester.pump();

    expect(controller.manualStates, [GarageDoorState.unknown]);
    expect(find.text('Status unbekannt'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dashboard highlights heuristic external origin', (tester) async {
    final controller = _FakeGarageDoorController(
      initialStatus: _status(
        state: GarageDoorState.unknown,
        stateConfidence: GarageDoorStateConfidence.heuristic,
        source: 'heuristic-external',
        description:
            'Heuristisch externer Shelly-Impuls waehrend laufender Bewegung erkannt. Status auf unbekannt gesetzt.',
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

    expect(find.text('Statusbasis'), findsOneWidget);
    expect(find.text('Heuristisch erkannt'), findsWidgets);
    expect(find.textContaining('Heuristisch extern erkannt:'), findsOneWidget);
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
    GarageDoorStatus? manualStatus,
  }) : _triggerStatus = triggerStatus ?? initialStatus,
       _manualStatus = manualStatus ?? initialStatus;

  final GarageDoorStatus initialStatus;
  final GarageDoorStatus _triggerStatus;
  final GarageDoorStatus _manualStatus;
  int triggerCalls = 0;
  final List<GarageDoorState> manualStates = [];

  @override
  Future<GarageDoorStatus> fetchStatus() async => initialStatus;

  @override
  Future<GarageDoorStatus> setManualState(GarageDoorState state) async {
    manualStates.add(state);
    return _manualStatus;
  }

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
  Future<GarageDoorStatus> setManualState(GarageDoorState state) async {
    throw UnimplementedError();
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
  String source = 'widget-test',
  String description = 'Widget test status',
}) {
  return GarageDoorStatus(
    state: state,
    stateConfidence: stateConfidence,
    nextState: null,
    phaseEndsAt: null,
    remainingMs: remainingMs,
    countdownLabel: countdownLabel,
    lastAction: GarageDoorLastAction(
      type: 'test',
      source: source,
      description: description,
      timestamp: DateTime.utc(2026, 4, 19, 12),
    ),
    shelly: const GarageDoorShellyStatus(isReachable: true, relayOutput: false),
  );
}
