import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/auth/autofill_focus_recovery.dart';
import '../features/logo_assets.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with AutofillFocusRecovery<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _authService = const AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    registerAutofillFocusNode(_emailFocusNode);
    registerAutofillFocusNode(_passwordFocusNode);
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
                            TextFormField(
                              controller: _emailController,
                              focusNode: _emailFocusNode,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [
                                AutofillHints.username,
                                AutofillHints.email,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'E-Mail',
                              ),
                              onTap: () {
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
                            TextFormField(
                              controller: _passwordController,
                              focusNode: _passwordFocusNode,
                              obscureText: _obscurePassword,
                              keyboardType: TextInputType.visiblePassword,
                              enableSuggestions: false,
                              autocorrect: false,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
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
                                markAutofillInteraction(_passwordFocusNode);
                              },
                              onFieldSubmitted: (_) => _submitLogin(),
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

  Future<void> _showForgotPasswordDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Passwort vergessen'),
          content: const Text(
            'Bitte wende dich an Felix Haader, Philipp Kern oder Tobias Halwax.',
          ),
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

  void _submitLogin() {
    if (_isLoading) return;
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
      TextInput.finishAutofillContext();
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
}
