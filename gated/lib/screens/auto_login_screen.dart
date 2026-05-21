import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../features/logo_assets.dart';
import '../services/auth_service.dart';
import '../services/credential_login_service.dart';

enum AutoLoginResultStatus { unsupported, empty, cancelled, error, authError }

class AutoLoginResult {
  const AutoLoginResult._(this.status, this.message);

  const AutoLoginResult.unsupported()
    : this._(
        AutoLoginResultStatus.unsupported,
        'Automatischer Login wird von diesem Browser nicht unterstützt. '
        'Bitte melde dich manuell an.',
      );

  const AutoLoginResult.empty()
    : this._(
        AutoLoginResultStatus.empty,
        'Es wurden keine gespeicherten Zugangsdaten gefunden. '
        'Bitte melde dich manuell an.',
      );

  const AutoLoginResult.cancelled()
    : this._(
        AutoLoginResultStatus.cancelled,
        'Automatischer Login wurde abgebrochen. '
        'Du kannst dich manuell anmelden.',
      );

  const AutoLoginResult.error()
    : this._(
        AutoLoginResultStatus.error,
        'Automatischer Login konnte nicht gestartet werden. '
        'Bitte melde dich manuell an.',
      );

  const AutoLoginResult.authError(String message)
    : this._(AutoLoginResultStatus.authError, message);

  final AutoLoginResultStatus status;
  final String message;
}

class AutoLoginScreen extends StatefulWidget {
  const AutoLoginScreen({
    super.key,
    AuthService? authService,
    CredentialLoginService? credentialLoginService,
  }) : _authService = authService,
       _credentialLoginService = credentialLoginService;

  final AuthService? _authService;
  final CredentialLoginService? _credentialLoginService;

  @override
  State<AutoLoginScreen> createState() => _AutoLoginScreenState();
}

class _AutoLoginScreenState extends State<AutoLoginScreen> {
  late final AuthService _authService;
  late final CredentialLoginService _credentialLoginService;

  String _statusText = 'Gespeicherte Zugangsdaten werden gesucht...';

  @override
  void initState() {
    super.initState();
    _authService = widget._authService ?? const AuthService();
    _credentialLoginService =
        widget._credentialLoginService ?? CredentialLoginService();
    unawaited(_runAutoLogin());
  }

  @override
  Widget build(BuildContext context) {
    final logoAsset = getFullLogoAsset(Theme.of(context).brightness);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 180, child: SvgPicture.asset(logoAsset)),
                const SizedBox(height: 24),
                Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _runAutoLogin() async {
    final credentialResult = await _credentialLoginService
        .getPasswordCredential();
    if (!mounted) {
      return;
    }

    if (!credentialResult.hasCredential) {
      _returnToLogin(_resultForStatus(credentialResult.status));
      return;
    }

    setState(() {
      _statusText = 'Anmeldung wird ausgeführt...';
    });

    try {
      await _authService.login(
        email: credentialResult.email!,
        password: credentialResult.password!,
      );
      unawaited(_authService.prefetchCurrentUser());
      if (!mounted) {
        return;
      }
      Navigator.pushReplacementNamed(context, '/home');
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      _returnToLogin(
        AutoLoginResult.authError(
          'Automatischer Login fehlgeschlagen: ${error.message} '
          'Bitte melde dich manuell an.',
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _returnToLogin(
        const AutoLoginResult.authError(
          'Automatischer Login fehlgeschlagen. Bitte melde dich manuell an.',
        ),
      );
    }
  }

  void _returnToLogin(AutoLoginResult result) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(result);
      return;
    }

    navigator.pushReplacementNamed('/login', arguments: result);
  }

  AutoLoginResult _resultForStatus(CredentialLoginStatus status) {
    return switch (status) {
      CredentialLoginStatus.unsupported => const AutoLoginResult.unsupported(),
      CredentialLoginStatus.empty => const AutoLoginResult.empty(),
      CredentialLoginStatus.cancelled => const AutoLoginResult.cancelled(),
      CredentialLoginStatus.error => const AutoLoginResult.error(),
      CredentialLoginStatus.success => const AutoLoginResult.authError(
        'Automatischer Login fehlgeschlagen. Bitte melde dich manuell an.',
      ),
    };
  }
}
