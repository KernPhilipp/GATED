import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _authService = const AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;

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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final logoAsset = isDarkMode
        ? 'assets/logo/logo-hell.png'
        : 'assets/logo/logo-dunkel.png';

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
                    padding: const EdgeInsets.all(10.0),
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
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'E-Mail',
                              ),
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
                                  return 'Bitte eine gultige E-Mail eingeben.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _passwordController,
                              focusNode: _passwordFocusNode,
                              obscureText: _obscurePassword,
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
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                ),
                              ),
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
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Login fehlgeschlagen. Bitte erneut versuchen.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    const duration = Duration(seconds: 3);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        action: SnackBarAction(
          label: 'Schließen',
          textColor: Theme.of(context).colorScheme.onError,
          onPressed: () {
            messenger.hideCurrentSnackBar();
          },
        ),
      ),
    );
    Future.delayed(duration, () {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
    });
  }
}
