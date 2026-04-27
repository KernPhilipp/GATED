import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../features/logo_assets.dart';
import '../features/pwa/pwa_install_controller.dart';
import '../services/app_metadata_service.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.onThemeModeChanged,
    required this.pwaInstallController,
    this.appMetadataService,
  });

  final ValueChanged<ThemeMode> onThemeModeChanged;
  final PwaInstallController pwaInstallController;
  final AppMetadataService? appMetadataService;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _authService = const AuthService();
  late final AppMetadataService _appMetadataService;
  String? _applicationVersion;

  @override
  void initState() {
    super.initState();
    _appMetadataService =
        widget.appMetadataService ?? const AppMetadataService();
    _loadApplicationVersion();
  }

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
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Abmelden'),
              subtitle: const Text('Aktuelle Sitzung beenden'),
              onTap: _handleLogout,
            ),
          ),
          const SizedBox(height: 15),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Ueber GATED'),
              subtitle: const Text('App-Informationen anzeigen'),
              onTap: _showAboutDialog,
            ),
          ),
          if (kIsWeb) ...[
            const SizedBox(height: 15),
            Card(
              child: ListenableBuilder(
                listenable: widget.pwaInstallController,
                builder: (context, _) {
                  final controller = widget.pwaInstallController;

                  return ListTile(
                    leading: Icon(
                      controller.isInstalled
                          ? Icons.check_circle_rounded
                          : Icons.install_desktop_rounded,
                    ),
                    title: Text(
                      controller.isInstalled
                          ? 'Web-App bereits installiert'
                          : 'Als Web-App installieren',
                    ),
                    subtitle: Text(
                      controller.statusMessage ??
                          'Die Installation wird direkt im Browser angeboten.',
                    ),
                    onTap: _handleInstallTap,
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showAboutDialog() {
    final logoAsset = getFullLogoAsset(Theme.of(context).brightness);

    showDialog<void>(
      context: context,
      builder: (context) {
        return AboutDialog(
          applicationName: 'GATED',
          applicationVersion: _applicationVersion ?? 'Version wird geladen...',
          applicationIcon: SvgPicture.asset(
            logoAsset,
            width: 60,
            fit: BoxFit.contain,
          ),
          children: const [
            Text('Developed by Philipp Kern, Tobias Halwax and Felix Haader.'),
            Text('Powered by HTL Hallein.'),
          ],
        );
      },
    );
  }

  Future<void> _loadApplicationVersion() async {
    try {
      final applicationVersion = await _appMetadataService.loadAppVersion();
      if (!mounted) {
        return;
      }

      setState(() {
        _applicationVersion = applicationVersion;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _applicationVersion = 'Unbekannt';
      });
    }
  }

  Future<void> _handleLogout() async {
    try {
      await _authService.logout();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: 'Abmeldung fehlgeschlagen.',
        isError: true,
        withCloseAction: true,
      );
    }
  }

  Future<void> _handleInstallTap() async {
    final controller = widget.pwaInstallController;

    if (!controller.isSupportedBrowser || controller.isInstalled) {
      showAppSnackBar(
        context,
        message:
            controller.statusMessage ??
            'Installations-Flow in diesem Browser nicht unterstuetzt.',
        withCloseAction: true,
      );
      return;
    }

    if (!controller.canPrompt) {
      showAppSnackBar(
        context,
        message:
            controller.statusMessage ??
            'Die Installation ist derzeit noch nicht verfuegbar.',
        withCloseAction: true,
      );
      return;
    }

    final result = await controller.promptInstall();
    if (!mounted) return;

    showAppSnackBar(
      context,
      message: switch (result) {
        PwaInstallPromptResult.installed => 'Installationsdialog gestartet.',
        PwaInstallPromptResult.dismissed =>
          'Die Installation wurde abgebrochen.',
        PwaInstallPromptResult.unavailable =>
          (controller.statusMessage ??
              'Die Installation ist derzeit noch nicht verfuegbar.'),
        PwaInstallPromptResult.unsupported =>
          'Installations-Flow in diesem Browser nicht unterstuetzt.',
        PwaInstallPromptResult.error =>
          'Die Installation konnte nicht gestartet werden.',
      },
      withCloseAction: true,
    );
  }
}
