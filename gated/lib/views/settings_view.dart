import 'package:flutter/material.dart';

import '../features/logo_assets.dart';
import '../services/auth_service.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.onThemeModeChanged});

  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _authService = const AuthService();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Einstellungen', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 20),
          Card(
            child: SwitchListTile(
              title: const Text('Dark Mode'),
              subtitle: const Text('Wechsel zwischen hellem und dunklem Theme'),
              value: isDarkMode,
              onChanged: (value) {
                widget.onThemeModeChanged(
                  value ? ThemeMode.dark : ThemeMode.light,
                );
              },
            ),
          ),
          const SizedBox(height: 15),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Abmelden'),
              subtitle: const Text('Aktuelle Sitzung beenden'),
              onTap: _handleLogout,
            ),
          ),
          const SizedBox(height: 15),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Über GATED'),
              subtitle: const Text('App-Informationen anzeigen'),
              onTap: _showAboutDialog,
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    final logoAsset = getFullLogoAsset(Theme.of(context).brightness);

    showAboutDialog(
      context: context,
      applicationName: 'GATED',
      applicationVersion: '1.0.0',
      applicationIcon: Image.asset(logoAsset, width: 60, fit: BoxFit.contain),
      children: const [
        Text('Developed by Philipp Kern, Tobias Halwax and Felix Haader.'),
        Text('Powered by HTL Hallein.'),
      ],
    );
  }

  Future<void> _handleLogout() async {
    try {
      await _authService.clearToken();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(content: Text('Abmeldung fehlgeschlagen.')),
      );
    }
  }
}
