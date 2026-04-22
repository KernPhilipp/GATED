import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/auth/autofill_focus_recovery.dart';
import '../features/auth/browser_autofill_text_field.dart';
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

class _RegisterScreenState extends State<RegisterScreen>
    with AutofillFocusRecovery<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  late final AuthService _authService;

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _authService = widget._authService ?? const AuthService();
    registerAutofillFocusNode(_emailFocusNode);
    registerAutofillFocusNode(_passwordFocusNode);
    registerAutofillController(
      _emailController,
      focusNode: _emailFocusNode,
      browserAutofillHints: const ['email', 'username'],
      onAutofillDetected: _handleAutofillCommit,
    );
    registerAutofillController(
      _passwordController,
      focusNode: _passwordFocusNode,
      browserAutofillHints: const ['new-password', 'password'],
      onAutofillDetected: _handleAutofillCommit,
    );
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
                        autovalidateMode: AutovalidateMode.onUserInteraction,
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
                            BrowserAutofillTextField(
                              controller: _emailController,
                              focusNode: _emailFocusNode,
                              autocomplete: 'email',
                              inputType: 'email',
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [
                                AutofillHints.email,
                                AutofillHints.username,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'E-Mail',
                              ),
                              onInteraction: () {
                                markAutofillInteraction(_emailFocusNode);
                              },
                              onFieldSubmitted: (_) => _focusPasswordField(),
                              validator: (value) {
                                final email = (value ?? '').trim();
                                if (email.isEmpty) {
                                  return 'Bitte E-Mail eingeben.';
                                }
                                final isValidEmail = RegExp(
                                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                ).hasMatch(email);
                                if (!isValidEmail) {
                                  return 'Bitte eine gültige E-Mail eingeben.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            BrowserAutofillTextField(
                              controller: _passwordController,
                              focusNode: _passwordFocusNode,
                              autocomplete: 'new-password',
                              inputType: 'password',
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
                              onInteraction: () {
                                markAutofillInteraction(_passwordFocusNode);
                              },
                              onFieldSubmitted: (_) => _submitRegister(),
                              validator: (value) {
                                if ((value ?? '').isEmpty) {
                                  return 'Bitte Passwort eingeben.';
                                }
                                return null;
                              },
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

  void _handleAutofillCommit() {
    if (!mounted) {
      return;
    }

    _formKey.currentState?.validate();
  }
}
