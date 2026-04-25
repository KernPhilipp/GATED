import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gated/screens/login_screen.dart';
import 'package:gated/screens/register_screen.dart';
import 'package:gated/services/auth_service.dart';
import 'package:gated/services/email_draft_service.dart';

void main() {
  testWidgets('login keeps warnings hidden until a field is touched', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/home': (_) => const Scaffold(body: Text('home')),
          '/register': (_) => const Scaffold(body: Text('register')),
        },
        home: LoginScreen(authService: _FakeLoginAuthService()),
      ),
    );

    expect(find.text('Bitte E-Mail eingeben.'), findsNothing);
    expect(find.text('Bitte Passwort eingeben.'), findsNothing);

    final fields = find.byType(TextFormField);
    await tester.tap(fields.first);
    await tester.pump();

    expect(find.text('Bitte E-Mail eingeben.'), findsOneWidget);
    expect(find.text('Bitte Passwort eingeben.'), findsNothing);
  });

  testWidgets('login submit marks both fields touched and shows warnings', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/home': (_) => const Scaffold(body: Text('home')),
          '/register': (_) => const Scaffold(body: Text('register')),
        },
        home: LoginScreen(authService: _FakeLoginAuthService()),
      ),
    );

    await tester.ensureVisible(find.text('Login'));
    await tester.tap(find.text('Login'));
    await tester.pump();

    expect(find.text('Bitte E-Mail eingeben.'), findsOneWidget);
    expect(find.text('Bitte Passwort eingeben.'), findsOneWidget);
  });

  testWidgets('register keeps warnings hidden until a field is touched', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {'/login': (_) => const Scaffold(body: Text('login'))},
        home: RegisterScreen(authService: _FakeRegisterAuthService()),
      ),
    );

    expect(find.text('Bitte E-Mail eingeben.'), findsNothing);
    expect(find.text('Bitte Passwort eingeben.'), findsNothing);

    final fields = find.byType(TextFormField);
    await tester.tap(fields.first);
    await tester.pump();

    expect(find.text('Bitte E-Mail eingeben.'), findsOneWidget);
    expect(find.text('Bitte Passwort eingeben.'), findsNothing);
  });

  testWidgets('register submit marks both fields touched and shows warnings', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {'/login': (_) => const Scaffold(body: Text('login'))},
        home: RegisterScreen(authService: _FakeRegisterAuthService()),
      ),
    );

    await tester.ensureVisible(find.text('Registrieren'));
    await tester.tap(find.text('Registrieren'));
    await tester.pump();

    expect(find.text('Bitte E-Mail eingeben.'), findsOneWidget);
    expect(find.text('Bitte Passwort eingeben.'), findsOneWidget);
  });

  testWidgets('forgot-password opens a prepared email draft', (tester) async {
    final emailDraftService = _FakeEmailDraftService();

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/home': (_) => const Scaffold(body: Text('home')),
          '/register': (_) => const Scaffold(body: Text('register')),
        },
        home: LoginScreen(
          authService: _FakeLoginAuthService(),
          emailDraftService: emailDraftService,
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextFormField).first,
      'user@example.com',
    );
    await tester.ensureVisible(find.text('Passwort vergessen?'));
    await tester.tap(find.text('Passwort vergessen?'));
    await tester.pumpAndSettle();

    expect(find.text('E-Mail oeffnen'), findsOneWidget);
    await tester.tap(find.text('E-Mail oeffnen'));
    await tester.pumpAndSettle();

    expect(emailDraftService.lastDraft, isNotNull);
    expect(
      emailDraftService.lastDraft!.to,
      'philipp.kern.student@htl-hallein.at',
    );
    expect(
      emailDraftService.lastDraft!.subject,
      'GATED-Passwort zuruecksetzen',
    );
    expect(
      emailDraftService.lastDraft!.body,
      contains('Zuruecksetzung meines GATED-Passworts'),
    );
    expect(
      emailDraftService.lastDraft!.body,
      contains('GATED-Account verknuepft ist'),
    );
  });
}

class _FakeLoginAuthService extends AuthService {
  _FakeLoginAuthService() : super(baseUrl: 'http://localhost');

  int loginCalls = 0;

  @override
  Future<void> login({required String email, required String password}) async {
    loginCalls++;
  }

  @override
  Future<void> prefetchCurrentUser() async {}
}

class _FakeRegisterAuthService extends AuthService {
  _FakeRegisterAuthService() : super(baseUrl: 'http://localhost');

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {}
}

class _FakeEmailDraftService extends EmailDraftService {
  EmailDraft? lastDraft;

  @override
  Future<bool> openDraft(EmailDraft draft) async {
    lastDraft = draft;
    return true;
  }
}
