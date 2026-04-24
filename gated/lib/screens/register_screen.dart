import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/logo_assets.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, AuthService? authService})
    : _authService = authService;

  final AuthService? _authService;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  late final AuthService _authService;

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isEmailTouched = false;
  bool _isPasswordTouched = false;

  @override
  void initState() {
    super.initState();
    _authService = widget._authService ?? const AuthService();
    _emailFocusNode.addListener(_handleEmailFocusChange);
    _passwordFocusNode.addListener(_handlePasswordFocusChange);
  }

  @override
  void dispose() {
    _emailFocusNode.removeListener(_handleEmailFocusChange);
    _passwordFocusNode.removeListener(_handlePasswordFocusChange);
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
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
                    child: AutofillGroup(
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
                              child: Image.asset(logoAsset),
                            ),
                            TextFormField(
                              controller: _emailController,
                              focusNode: _emailFocusNode,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [
                                AutofillHints.email,
                                AutofillHints.username,
                              ],
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
                              autofillHints: const [AutofillHints.newPassword],
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
                              onFieldSubmitted: (_) => _submitRegister(),
                              validator: _validatePasswordField,
                            ),
                            const SizedBox(height: 40),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _isLoading ? null : _submitRegister,
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
                                    : const Text('Registrieren'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: () {
                                Navigator.pushReplacementNamed(
                                  context,
                                  '/login',
                                );
                              },
                              child: const Text(
                                'Schon einen Account? Anmelden',
                              ),
                            ),
                          ],
                        ),
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

  void _submitRegister() {
    if (_isLoading) return;
    _markAllFieldsTouched();
    if (_formKey.currentState?.validate() == false) return;
    FocusScope.of(context).unfocus();
    _handleRegister();
  }

  Future<void> _handleRegister() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() => _isLoading = true);

    try {
      await _authService.register(email: email, password: password);
      TextInput.finishAutofillContext(shouldSave: true);
      if (!mounted) return;
      if (_isLoading) {
        setState(() => _isLoading = false);
      }
      await _showRegistrationSuccessDialog();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
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
        message: 'Registrierung fehlgeschlagen. Bitte erneut versuchen.',
        isError: true,
        withCloseAction: true,
      );
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showRegistrationSuccessDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Registrierung erfolgreich'),
          content: const Text(
            'Dein Account wurde erstellt. Bitte melde dich jetzt an.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Zum Login'),
            ),
          ],
        );
      },
    );
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
