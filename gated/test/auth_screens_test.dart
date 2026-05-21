import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gated/screens/auto_login_screen.dart';
import 'package:gated/screens/login_screen.dart';
import 'package:gated/screens/register_screen.dart';
import 'package:gated/services/auth_service.dart';
import 'package:gated/services/credential_login_service.dart';
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

  testWidgets('login fields do not expose autofill hints', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/home': (_) => const Scaffold(body: Text('home')),
          '/register': (_) => const Scaffold(body: Text('register')),
        },
        home: LoginScreen(authService: _FakeLoginAuthService()),
      ),
    );

    final editables = find.byType(EditableText);
    expect(editables, findsNWidgets(2));
    expect(tester.widget<EditableText>(editables.first).autofillHints, isNull);
    expect(tester.widget<EditableText>(editables.last).autofillHints, isNull);
    expect(find.byType(AutofillGroup), findsNothing);
  });

  testWidgets('automatic login button navigates to auto-login route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/home': (_) => const Scaffold(body: Text('home')),
          '/register': (_) => const Scaffold(body: Text('register')),
          '/auto-login': (_) => const Scaffold(body: Text('auto-login')),
        },
        home: LoginScreen(authService: _FakeLoginAuthService()),
      ),
    );

    await tester.ensureVisible(find.text('Automatischer Login'));
    await tester.tap(find.text('Automatischer Login'));
    await tester.pumpAndSettle();

    expect(find.text('auto-login'), findsOneWidget);
  });

  testWidgets('automatic login cancellation shows cancellation dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/home': (_) => const Scaffold(body: Text('home')),
          '/register': (_) => const Scaffold(body: Text('register')),
          '/auto-login': (_) => AutoLoginScreen(
            authService: _FakeLoginAuthService(),
            credentialLoginService: _FakeCredentialLoginService(
              result: const CredentialLoginResult.cancelled(),
            ),
          ),
        },
        home: LoginScreen(authService: _FakeLoginAuthService()),
      ),
    );

    await tester.ensureVisible(find.text('Automatischer Login'));
    await tester.tap(find.text('Automatischer Login'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.textContaining('wurde abgebrochen'), findsOneWidget);
    expect(
      find.textContaining('Du kannst dich manuell anmelden'),
      findsOneWidget,
    );
  });

  testWidgets('manual login stores credentials best-effort', (tester) async {
    final credentialLoginService = _FakeCredentialLoginService();

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/home': (_) => const Scaffold(body: Text('home')),
          '/register': (_) => const Scaffold(body: Text('register')),
        },
        home: LoginScreen(
          authService: _FakeLoginAuthService(),
          credentialLoginService: credentialLoginService,
        ),
      ),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'user@example.com');
    await tester.enterText(fields.last, 'secret');
    await tester.ensureVisible(find.text('Login'));
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(credentialLoginService.lastStoredEmail, 'user@example.com');
    expect(credentialLoginService.lastStoredPassword, 'secret');
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

  testWidgets('register fields do not expose autofill hints', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {'/login': (_) => const Scaffold(body: Text('login'))},
        home: RegisterScreen(authService: _FakeRegisterAuthService()),
      ),
    );

    final editables = find.byType(EditableText);
    expect(editables, findsNWidgets(2));
    expect(tester.widget<EditableText>(editables.first).autofillHints, isNull);
    expect(tester.widget<EditableText>(editables.last).autofillHints, isNull);
    expect(find.byType(AutofillGroup), findsNothing);
  });

  testWidgets('manual register stores credentials best-effort', (tester) async {
    final credentialLoginService = _FakeCredentialLoginService();

    await tester.pumpWidget(
      MaterialApp(
        routes: {'/login': (_) => const Scaffold(body: Text('login'))},
        home: RegisterScreen(
          authService: _FakeRegisterAuthService(),
          credentialLoginService: credentialLoginService,
        ),
      ),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'new@example.com');
    await tester.enterText(fields.last, 'secret');
    await tester.ensureVisible(find.text('Registrieren'));
    await tester.tap(find.text('Registrieren'));
    await tester.pumpAndSettle();

    expect(find.text('Registrierung erfolgreich'), findsOneWidget);
    expect(credentialLoginService.lastStoredEmail, 'new@example.com');
    expect(credentialLoginService.lastStoredPassword, 'secret');
  });

  testWidgets('auto-login success navigates to home', (tester) async {
    final authService = _FakeLoginAuthService();
    final credentialLoginService = _FakeCredentialLoginService(
      result: const CredentialLoginResult.success(
        email: 'user@example.com',
        password: 'secret',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/home': (_) => const Scaffold(body: Text('home')),
          '/login': (_) => const Scaffold(body: Text('login')),
        },
        home: AutoLoginScreen(
          authService: authService,
          credentialLoginService: credentialLoginService,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(authService.loginCalls, 1);
    expect(authService.lastLoginEmail, 'user@example.com');
    expect(authService.lastLoginPassword, 'secret');
  });

  testWidgets('auto-login unsupported returns to login and shows dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/home': (_) => const Scaffold(body: Text('home')),
          '/login': (_) => LoginScreen(authService: _FakeLoginAuthService()),
        },
        home: AutoLoginScreen(
          authService: _FakeLoginAuthService(),
          credentialLoginService: _FakeCredentialLoginService(
            result: const CredentialLoginResult.unsupported(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.textContaining('nicht'), findsOneWidget);
  });

  testWidgets('auto-login empty returns to login and shows dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/home': (_) => const Scaffold(body: Text('home')),
          '/login': (_) => LoginScreen(authService: _FakeLoginAuthService()),
        },
        home: AutoLoginScreen(
          authService: _FakeLoginAuthService(),
          credentialLoginService: _FakeCredentialLoginService(
            result: const CredentialLoginResult.empty(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      find.textContaining('keine gespeicherten Zugangsdaten'),
      findsOneWidget,
    );
  });

  testWidgets('auto-login error returns to login and shows dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/home': (_) => const Scaffold(body: Text('home')),
          '/login': (_) => LoginScreen(authService: _FakeLoginAuthService()),
        },
        home: AutoLoginScreen(
          authService: _FakeLoginAuthService(),
          credentialLoginService: _FakeCredentialLoginService(
            result: const CredentialLoginResult.error(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      find.textContaining('konnte nicht gestartet werden'),
      findsOneWidget,
    );
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

    expect(find.text('E-Mail öffnen'), findsOneWidget);
    await tester.tap(find.text('E-Mail öffnen'));
    await tester.pumpAndSettle();

    expect(emailDraftService.lastDraft, isNotNull);
    expect(
      emailDraftService.lastDraft!.to,
      'philipp.kern.student@htl-hallein.at',
    );
    expect(emailDraftService.lastDraft!.subject, 'GATED-Passwort zurücksetzen');
    expect(
      emailDraftService.lastDraft!.body,
      contains('Zurücksetzung meines GATED-Passworts'),
    );
    expect(
      emailDraftService.lastDraft!.body,
      contains('GATED-Account verknüpft ist'),
    );
  });
}

class _FakeLoginAuthService extends AuthService {
  _FakeLoginAuthService() : super(baseUrl: 'http://localhost');

  int loginCalls = 0;
  String? lastLoginEmail;
  String? lastLoginPassword;

  @override
  Future<void> login({required String email, required String password}) async {
    loginCalls++;
    lastLoginEmail = email;
    lastLoginPassword = password;
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

class _FakeCredentialLoginService extends CredentialLoginService {
  _FakeCredentialLoginService({
    this.result = const CredentialLoginResult.unsupported(),
  }) : super.internal();

  final CredentialLoginResult result;
  String? lastStoredEmail;
  String? lastStoredPassword;

  @override
  Future<CredentialLoginResult> getPasswordCredential() async {
    return result;
  }

  @override
  Future<void> storePasswordCredential({
    required String email,
    required String password,
  }) async {
    lastStoredEmail = email;
    lastStoredPassword = password;
  }
}
