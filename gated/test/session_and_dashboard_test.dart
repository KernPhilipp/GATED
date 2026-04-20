import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gated/features/auth/session_expiration.dart';
import 'package:gated/services/auth_service.dart';
import 'package:gated/services/garage_door_service.dart';
import 'package:gated/views/dashboard_view.dart';

void main() {
  testWidgets('dashboard waits for activation before polling', (tester) async {
    final controller = _FakeGarageDoorController(
      status: _status(
        state: GarageDoorState.closed,
        stateConfidence: GarageDoorStateConfidence.modeled,
      ),
    );
    const key = ValueKey('dashboard');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DashboardView(
              key: key,
              isActive: false,
              garageDoorController: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(controller.fetchCalls, 0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DashboardView(
              key: key,
              isActive: true,
              garageDoorController: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(controller.fetchCalls, greaterThanOrEqualTo(1));
    expect(find.text('Tor geschlossen'), findsOneWidget);
  });

  testWidgets('logout session end redirects without expiration dialog', (
    tester,
  ) async {
    final authService = _FakeAuthService();

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/': (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  redirectToLoginAfterSessionExpired(
                    context,
                    authService: authService,
                    message: 'Du wurdest abgemeldet.',
                    reason: AuthSessionEndReason.logout,
                  );
                },
                child: const Text('logout'),
              ),
            ),
          ),
          '/login': (context) => const Scaffold(body: Text('login')),
        },
      ),
    );

    await tester.tap(find.text('logout'));
    await tester.pumpAndSettle();

    expect(authService.clearReason, AuthSessionEndReason.logout);
    expect(find.text('login'), findsOneWidget);
    expect(find.text('Sitzung abgelaufen'), findsNothing);
  });
}

class _FakeGarageDoorController implements GarageDoorController {
  _FakeGarageDoorController({required this.status});

  final GarageDoorStatus status;
  int fetchCalls = 0;

  @override
  Future<GarageDoorStatus> fetchStatus() async {
    fetchCalls++;
    return status;
  }

  @override
  Future<GarageDoorStatus> setManualState(GarageDoorState state) async =>
      status;

  @override
  Future<GarageDoorStatus> triggerPulse() async => status;
}

class _FakeAuthService extends AuthService {
  _FakeAuthService() : super(baseUrl: 'http://localhost');

  AuthSessionEndReason? clearReason;

  @override
  Future<void> clearTokens({
    AuthSessionEndReason reason = AuthSessionEndReason.expired,
  }) async {
    clearReason = reason;
  }
}

GarageDoorStatus _status({
  required GarageDoorState state,
  required GarageDoorStateConfidence stateConfidence,
}) {
  return GarageDoorStatus(
    state: state,
    stateConfidence: stateConfidence,
    nextState: null,
    phaseEndsAt: null,
    remainingMs: null,
    countdownLabel: null,
    lastAction: GarageDoorLastAction(
      type: 'test',
      source: 'widget-test',
      description: 'Widget test status',
      timestamp: DateTime.utc(2026, 4, 19, 12),
    ),
    shelly: const GarageDoorShellyStatus(isReachable: true, relayOutput: false),
  );
}
