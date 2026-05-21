import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../features/logo_assets.dart';
import '../screens/auto_login_screen.dart';
import '../services/auth_service.dart';
import '../services/credential_login_service.dart';
import '../services/email_draft_service.dart';
import '../services/manual_password_autofill_suppressor.dart';
import '../utils/snackbar_utils.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    AuthService? authService,
    EmailDraftService? emailDraftService,
    CredentialLoginService? credentialLoginService,
  }) : _authService = authService,
       _emailDraftService = emailDraftService,
       _credentialLoginService = credentialLoginService;

  final AuthService? _authService;
  final EmailDraftService? _emailDraftService;
  final CredentialLoginService? _credentialLoginService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  late final AuthService _authService;
  late final EmailDraftService _emailDraftService;
  late final CredentialLoginService _credentialLoginService;
  late final ManualPasswordAutofillSuppressor _manualPasswordAutofillSuppressor;

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isEmailTouched = false;
  bool _isPasswordTouched = false;
  bool _autoLoginDialogShown = false;

  @override
  void initState() {
    super.initState();
    _authService = widget._authService ?? const AuthService();
    _emailDraftService = widget._emailDraftService ?? const EmailDraftService();
    _credentialLoginService =
        widget._credentialLoginService ?? CredentialLoginService();
    _manualPasswordAutofillSuppressor = ManualPasswordAutofillSuppressor()
      ..install();
    _emailFocusNode.addListener(_handleEmailFocusChange);
    _passwordFocusNode.addListener(_handlePasswordFocusChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_autoLoginDialogShown) {
      return;
    }

    final arguments = ModalRoute.of(context)?.settings.arguments;
    final message = switch (arguments) {
      final AutoLoginResult result => result.message,
      final String value when value.isNotEmpty => value,
      _ => null,
    };
    if (message == null) return;

    _autoLoginDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showAutoLoginDialog(message);
    });
  }

  @override
  void dispose() {
    _emailFocusNode.removeListener(_handleEmailFocusChange);
    _passwordFocusNode.removeListener(_handlePasswordFocusChange);
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _manualPasswordAutofillSuppressor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final logoAsset = getFullLogoAsset(Theme.of(context).brightness);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Padding(
                    padding: const EdgeInsets.all(30.0),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.always,
                      child: Column(
                        children: [
                          const Text(
                            'Willkommen bei',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 50,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(
                            height: 200,
                            child: SvgPicture.asset(logoAsset),
                          ),
                          TextFormField(
                            controller: _emailController,
                            focusNode: _emailFocusNode,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'E-Mail',
                            ),
                            onTap: () {
                              _markEmailTouched();
                            },
                            onFieldSubmitted: (_) => _focusPasswordField(),
                            validator: _validateEmailField,
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _passwordController,
                            focusNode: _passwordFocusNode,
                            obscureText: _obscurePassword,
                            keyboardType: TextInputType.visiblePassword,
                            enableSuggestions: false,
                            autocorrect: false,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: 'Passwort',
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Passwort anzeigen'
                                    : 'Passwort verbergen',
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                ),
                              ),
                            ),
                            onTap: () {
                              _markPasswordTouched();
                            },
                            onFieldSubmitted: (_) => _submitLogin(),
                            validator: _validatePasswordField,
                          ),
                          const SizedBox(height: 40),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _isLoading ? null : _submitLogin,
                              style: FilledButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                      ),
                                    )
                                  : const Text('Login'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () {
                              Navigator.pushReplacementNamed(
                                context,
                                '/register',
                              );
                            },
                            child: const Text(
                              'Noch keinen Account? Registrieren',
                            ),
                          ),
                          const SizedBox(height: 5),
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : _showForgotPasswordDialog,
                            child: const Text('Passwort vergessen?'),
                          ),
                          const SizedBox(height: 5),
                          TextButton(
                            onPressed: _isLoading ? null : _openAutoLogin,
                            child: const Text('Automatischer Login'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _focusPasswordField() {
    FocusScope.of(context).requestFocus(_passwordFocusNode);
  }

  Future<void> _openAutoLogin() async {
    final result = await Navigator.of(context).pushNamed('/auto-login');
    if (!mounted || result is! AutoLoginResult) {
      return;
    }

    await _showAutoLoginDialog(result.message);
  }

  Future<void> _showAutoLoginDialog(String message) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Automatischer Login'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showForgotPasswordDialog() async {
    final shouldOpenMail = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: const Text('Passwort vergessen'),
          content: const Text(
            'Wenn du dein Passwort zurücksetzen lassen möchtest, wird eine '
            'vorbereitete E-Mail an philipp.kern.student@htl-hallein.at '
            'geöffnet.\n\nWichtig: Diese E-Mail muss von derselben '
            'E-Mail-Adresse gesendet werden, die mit deinem GATED-Account '
            'verknüpft ist.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('E-Mail öffnen'),
            ),
          ],
        );
      },
    );

    if (shouldOpenMail != true || !mounted) {
      return;
    }

    final opened = await _emailDraftService.openDraft(
      EmailDraft(
        to: 'philipp.kern.student@htl-hallein.at',
        subject: 'GATED-Passwort zurücksetzen',
        body:
            'Sehr geehrter Herr Kern,\n\n'
            'ich bitte um die Zurücksetzung meines GATED-Passworts.\n'
            'Diese Anfrage wird von der E-Mail-Adresse gesendet, die mit '
            'meinem GATED-Account verknüpft ist.\n\n'
            'Vielen Dank im Voraus.\n\n'
            'Mit freundlichen Grüßen',
      ),
    );

    if (!mounted) {
      return;
    }

    if (!opened) {
      showAppSnackBar(
        context,
        message: 'Die E-Mail-App konnte nicht geöffnet werden.',
        isError: true,
        withCloseAction: true,
      );
    }
  }

  void _submitLogin() {
    if (_isLoading) return;
    _markAllFieldsTouched();
    if (_formKey.currentState?.validate() == false) return;
    FocusScope.of(context).unfocus();
    _handleLogin();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() => _isLoading = true);

    try {
      await _authService.login(email: email, password: password);
      unawaited(
        _credentialLoginService.storePasswordCredential(
          email: email,
          password: password,
        ),
      );
      unawaited(_authService.prefetchCurrentUser());
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } on AuthException catch (e) {
      showAppSnackBar(
        context,
        message: e.message,
        isError: true,
        withCloseAction: true,
      );
    } catch (_) {
      showAppSnackBar(
        context,
        message: 'Login fehlgeschlagen. Bitte erneut versuchen.',
        isError: true,
        withCloseAction: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleEmailFocusChange() {
    if (_emailFocusNode.hasFocus) {
      _markEmailTouched();
    }
  }

  void _handlePasswordFocusChange() {
    if (_passwordFocusNode.hasFocus) {
      _markPasswordTouched();
    }
  }

  void _markEmailTouched() {
    if (_isEmailTouched) {
      return;
    }

    setState(() {
      _isEmailTouched = true;
    });
  }

  void _markPasswordTouched() {
    if (_isPasswordTouched) {
      return;
    }

    setState(() {
      _isPasswordTouched = true;
    });
  }

  void _markAllFieldsTouched() {
    if (_isEmailTouched && _isPasswordTouched) {
      return;
    }

    setState(() {
      _isEmailTouched = true;
      _isPasswordTouched = true;
    });
  }

  String? _validateEmailField(String? value) {
    if (!_isEmailTouched) {
      return null;
    }

    return _rawEmailValidationMessage(value);
  }

  String? _validatePasswordField(String? value) {
    if (!_isPasswordTouched) {
      return null;
    }

    return _rawPasswordValidationMessage(value);
  }

  String? _rawEmailValidationMessage(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) {
      return 'Bitte E-Mail eingeben.';
    }

    if (!_emailPattern.hasMatch(email)) {
      return 'Bitte eine gültige E-Mail eingeben.';
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
