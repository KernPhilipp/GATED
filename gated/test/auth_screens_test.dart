import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gated/features/auth/autofill_focus_recovery.dart';
import 'package:gated/screens/login_screen.dart';
import 'package:gated/screens/register_screen.dart';
import 'package:gated/services/auth_service.dart';

void main() {
  tearDown(() {
    debugTreatAutofillAsWeb = false;
  });

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

  testWidgets('login auto submits once after first valid autofill', (
    tester,
  ) async {
    debugTreatAutofillAsWeb = true;
    await tester.pumpWidget(
      const MaterialApp(home: _AutofillAutoSubmitHarness()),
    );

    final controllers = _fieldControllers(tester);
    controllers[0].value = const TextEditingValue(
      text: 'user@example.com',
      selection: TextSelection.collapsed(offset: 16),
    );
    controllers[1].value = const TextEditingValue(
      text: 'secret123',
      selection: TextSelection.collapsed(offset: 9),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('submitCalls: 1'), findsOneWidget);

    controllers[0].value = const TextEditingValue(
      text: 'other@example.com',
      selection: TextSelection.collapsed(offset: 17),
    );
    controllers[1].value = const TextEditingValue(
      text: 'another-secret',
      selection: TextSelection.collapsed(offset: 14),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('submitCalls: 1'), findsOneWidget);
  });

  testWidgets('login does not auto submit for partial autofill', (
    tester,
  ) async {
    debugTreatAutofillAsWeb = true;
    await tester.pumpWidget(
      const MaterialApp(home: _AutofillAutoSubmitHarness()),
    );

    final controllers = _fieldControllers(tester);
    controllers[0].value = const TextEditingValue(
      text: 'user@example.com',
      selection: TextSelection.collapsed(offset: 16),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('submitCalls: 0'), findsOneWidget);
  });
}

List<TextEditingController> _fieldControllers(WidgetTester tester) {
  return tester
      .widgetList<TextFormField>(find.byType(TextFormField))
      .map((field) => field.controller!)
      .toList();
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

class _AutofillAutoSubmitHarness extends StatefulWidget {
  const _AutofillAutoSubmitHarness();

  @override
  State<_AutofillAutoSubmitHarness> createState() =>
      _AutofillAutoSubmitHarnessState();
}

class _AutofillAutoSubmitHarnessState
    extends State<_AutofillAutoSubmitHarness>
    with AutofillFocusRecovery<_AutofillAutoSubmitHarness> {
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _initialAutofillAutoSubmitAvailable = true;
  int _submitCalls = 0;

  @override
  void initState() {
    super.initState();
    registerAutofillController(
      _emailController,
      focusNode: _emailFocusNode,
      browserAutofillHints: const ['email', 'username'],
      onAutofillDetected: _handleAutofill,
      onUserInputDetected: _disableAutoSubmit,
    );
    registerAutofillController(
      _passwordController,
      focusNode: _passwordFocusNode,
      browserAutofillHints: const ['current-password', 'password'],
      onAutofillDetected: _handleAutofill,
      onUserInputDetected: _disableAutoSubmit,
    );
    markAutofillInteraction(_emailFocusNode);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Column(
        children: [
          TextFormField(controller: _emailController, focusNode: _emailFocusNode),
          TextFormField(
            controller: _passwordController,
            focusNode: _passwordFocusNode,
          ),
          Text('submitCalls: $_submitCalls'),
        ],
      ),
    );
  }

  void _handleAutofill() {
    if (!_initialAutofillAutoSubmitAvailable) {
      return;
    }

    if (_rawEmailValidationMessage(_emailController.text) != null ||
        _rawPasswordValidationMessage(_passwordController.text) != null) {
      return;
    }

    setState(() {
      _initialAutofillAutoSubmitAvailable = false;
      _submitCalls++;
    });
  }

  void _disableAutoSubmit() {
    _initialAutofillAutoSubmitAvailable = false;
  }

  String? _rawEmailValidationMessage(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) {
      return 'Bitte E-Mail eingeben.';
    }

    if (!_emailPattern.hasMatch(email)) {
      return 'Bitte eine gueltige E-Mail eingeben.';
    }

    return null;
  }

  String? _rawPasswordValidationMessage(String? value) {
    if ((value ?? '').isEmpty) {
      return 'Bitte Passwort eingeben.';
    }

    return null;
  }
}
