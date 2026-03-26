import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/auth/session_expiration.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final _authService = const AuthService();
  GlobalKey<FormState> _passwordFormKey = GlobalKey<FormState>();
  TextEditingController _currentPasswordController = TextEditingController();
  TextEditingController _newPasswordController = TextEditingController();
  TextEditingController _confirmPasswordController = TextEditingController();

  AuthUser? _user;
  String? _profileError;
  bool _isLoadingProfile = true;
  bool _isChangingPassword = false;
  bool _isRedirectingToLogin = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  int _passwordFormVersion = 0;

  @override
  void initState() {
    super.initState();
    _user = _authService.cachedCurrentUser;
    _isLoadingProfile = _user == null;

    if (_user == null) {
      _loadProfile();
    }
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Profil', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWideLayout = constraints.maxWidth >= 750;
              final profileCard = _buildProfileCard(theme);
              final passwordCard = _buildPasswordCard(theme);

              if (isWideLayout) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: profileCard),
                    const SizedBox(width: 24),
                    Expanded(child: passwordCard),
                  ],
                );
              }

              return Column(
                children: [
                  profileCard,
                  const SizedBox(height: 20),
                  passwordCard,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(ThemeData theme) {
    if (_isLoadingProfile) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Profil wird geladen...',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_profileError != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: theme.colorScheme.error,
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                'Profil konnte nicht geladen werden',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(_profileError!),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _loadProfile(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
      );
    }

    final user = _user;
    if (user == null) {
      return const SizedBox.shrink();
    }

    final initial = user.email.isNotEmpty
        ? user.email.characters.first.toUpperCase()
        : '?';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Text(initial, style: theme.textTheme.headlineSmall),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.email, style: theme.textTheme.titleLarge),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _ProfileInfoRow(
              icon: Icons.mail_outline_rounded,
              label: 'E-Mail',
              value: user.email,
            ),
            const SizedBox(height: 14),
            _ProfileInfoRow(
              icon: Icons.event_outlined,
              label: 'Registriert seit',
              value: _formatCreatedAt(user.createdAt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AutofillGroup(
          key: ValueKey(_passwordFormVersion),
          child: Form(
            key: _passwordFormKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Passwort ändern', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Zur Sicherheit wird zuerst dein aktuelles Passwort geprüft.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _currentPasswordController,
                  obscureText: _obscureCurrentPassword,
                  keyboardType: TextInputType.visiblePassword,
                  enableSuggestions: false,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Aktuelles Passwort',
                    suffixIcon: IconButton(
                      tooltip: _obscureCurrentPassword
                          ? 'Passwort anzeigen'
                          : 'Passwort verbergen',
                      onPressed: () {
                        setState(() {
                          _obscureCurrentPassword = !_obscureCurrentPassword;
                        });
                      },
                      icon: Icon(
                        _obscureCurrentPassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if ((value ?? '').isEmpty) {
                      return 'Bitte aktuelles Passwort eingeben.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: _obscureNewPassword,
                  keyboardType: TextInputType.visiblePassword,
                  enableSuggestions: false,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'Neues Passwort',
                    suffixIcon: IconButton(
                      tooltip: _obscureNewPassword
                          ? 'Passwort anzeigen'
                          : 'Passwort verbergen',
                      onPressed: () {
                        setState(() {
                          _obscureNewPassword = !_obscureNewPassword;
                        });
                      },
                      icon: Icon(
                        _obscureNewPassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if ((value ?? '').isEmpty) {
                      return 'Bitte neues Passwort eingeben.';
                    }
                    if (value == _currentPasswordController.text) {
                      return 'Bitte ein anderes Passwort wählen.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  keyboardType: TextInputType.visiblePassword,
                  enableSuggestions: false,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'Neues Passwort bestätigen',
                    suffixIcon: IconButton(
                      tooltip: _obscureConfirmPassword
                          ? 'Passwort anzeigen'
                          : 'Passwort verbergen',
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if ((value ?? '').isEmpty) {
                      return 'Bitte Passwort bestätigen.';
                    }
                    if (value != _newPasswordController.text) {
                      return 'Die Passwörter stimmen nicht überein.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isChangingPassword
                        ? null
                        : _submitPasswordChange,
                    icon: _isChangingPassword
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          )
                        : const Icon(Icons.lock_reset_rounded),
                    label: Text(
                      _isChangingPassword
                          ? 'Passwort wird geändert...'
                          : 'Passwort aktualisieren',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadProfile({bool forceRefresh = false}) async {
    if (_isRedirectingToLogin) {
      return;
    }

    setState(() {
      _isLoadingProfile = true;
      _profileError = null;
    });

    try {
      final user = forceRefresh
          ? await _authService.refreshCurrentUser()
          : await _authService.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _user = user;
        _isLoadingProfile = false;
      });
    } on SessionExpiredException catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingProfile = false);
      await _handleSessionExpired(e.message);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _profileError = e.message;
        _isLoadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profileError =
            'Beim Laden des Profils ist ein unerwarteter Fehler aufgetreten.';
        _isLoadingProfile = false;
      });
    }
  }

  Future<void> _submitPasswordChange() async {
    if (_isChangingPassword) {
      return;
    }

    if (_passwordFormKey.currentState?.validate() == false) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isChangingPassword = true);

    try {
      await _authService.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      _resetPasswordForm();
      await _showPasswordChangedDialog();
    } on SessionExpiredException catch (e) {
      if (!mounted) return;
      _resetPasswordForm();
      await _handleSessionExpired(e.message);
    } on AuthException catch (e) {
      if (!mounted) return;
      _resetPasswordForm();
      showAppSnackBar(
        context,
        message: e.message,
        isError: true,
        withCloseAction: true,
      );
    } catch (_) {
      if (!mounted) return;
      _resetPasswordForm();
      showAppSnackBar(
        context,
        message: 'Passwortänderung fehlgeschlagen. Bitte erneut versuchen.',
        isError: true,
        withCloseAction: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isChangingPassword = false);
      }
    }
  }

  void _resetPasswordForm() {
    FocusManager.instance.primaryFocus?.unfocus();
    TextInput.finishAutofillContext(shouldSave: false);

    final oldCurrentPasswordController = _currentPasswordController;
    final oldNewPasswordController = _newPasswordController;
    final oldConfirmPasswordController = _confirmPasswordController;

    setState(() {
      _passwordFormKey = GlobalKey<FormState>();
      _currentPasswordController = TextEditingController();
      _newPasswordController = TextEditingController();
      _confirmPasswordController = TextEditingController();
      _obscureCurrentPassword = true;
      _obscureNewPassword = true;
      _obscureConfirmPassword = true;
      _passwordFormVersion++;
    });

    oldCurrentPasswordController.dispose();
    oldNewPasswordController.dispose();
    oldConfirmPasswordController.dispose();
  }

  Future<void> _showPasswordChangedDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Passwort aktualisiert'),
          content: const Text('Dein Passwort wurde erfolgreich aktualisiert.'),
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

  Future<void> _handleSessionExpired(String message) async {
    if (_isRedirectingToLogin) {
      return;
    }

    _isRedirectingToLogin = true;
    await redirectToLoginAfterSessionExpired(
      context,
      authService: _authService,
      message: message,
    );
  }

  String _formatCreatedAt(DateTime? createdAt) {
    if (createdAt == null) {
      return 'Nicht verfügbar';
    }

    final day = createdAt.day.toString().padLeft(2, '0');
    final month = createdAt.month.toString().padLeft(2, '0');
    final year = createdAt.year.toString();
    final hour = createdAt.hour.toString().padLeft(2, '0');
    final minute = createdAt.minute.toString().padLeft(2, '0');

    return '$day.$month.$year, $hour:$minute';
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}
