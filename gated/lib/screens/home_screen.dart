import 'dart:async';

import 'package:flutter/material.dart';

import '../features/navbar/navbar.dart';
import '../features/pwa/pwa_install_controller.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';
import '../views/dashboard_view.dart';
import '../views/kennzeichen_view.dart';
import '../views/profile_view.dart';
import '../views/settings_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onThemeModeChanged,
    required this.pwaInstallController,
  });

  final ValueChanged<ThemeMode> onThemeModeChanged;
  final PwaInstallController pwaInstallController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _authService = const AuthService();
  int _selectedIndex = 0;

  final List<({String label, IconData icon})> _navItems = [
    (label: 'Dashboard', icon: Icons.dashboard_rounded),
    (label: 'Kennzeichen', icon: Icons.view_list_rounded),
    (label: 'Profil', icon: Icons.person_rounded),
    (label: 'Einstellungen', icon: Icons.settings_rounded),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_authService.prefetchCurrentUser());
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isPhone = width < 500;
    final banner = _buildInstallBanner(context);

    final content = _HomeContent(
      selectedIndex: _selectedIndex,
      children: [
        DashboardView(
          key: const ValueKey('dashboard-view'),
          isActive: _selectedIndex == 0,
        ),
        KennzeichenView(
          key: const ValueKey('kennzeichen-view'),
          isActive: _selectedIndex == 1,
        ),
        const ProfileView(key: ValueKey('profile-view')),
        SettingsView(
          key: const ValueKey('settings-view'),
          onThemeModeChanged: widget.onThemeModeChanged,
          pwaInstallController: widget.pwaInstallController,
        ),
      ],
    );

    return Scaffold(
      body: isPhone
          ? Column(
              children: [
                banner,
                Expanded(child: content),
              ],
            )
          : Row(
              children: [
                NavigationSidebar(
                  items: _navItems,
                  selectedIndex: _selectedIndex,
                  onTap: _onNavTap,
                ),
                Expanded(
                  child: Column(
                    children: [
                      banner,
                      Expanded(child: content),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: isPhone
          ? NavigationBarTheme(
              data: NavigationBarThemeData(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return IconThemeData(
                      color: Theme.of(context).colorScheme.secondary,
                    );
                  }
                  return IconThemeData(
                    color: Theme.of(context).colorScheme.primary,
                  );
                }),
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                      fontWeight: FontWeight.w700,
                    );
                  }
                  return TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.normal,
                  );
                }),
              ),
              child: NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _onNavTap,
                destinations: [
                  for (final item in _navItems)
                    NavigationDestination(
                      icon: Icon(item.icon),
                      label: item.label,
                    ),
                ],
              ),
            )
          : null,
    );
  }

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);
  }

  Widget _buildInstallBanner(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.pwaInstallController,
      builder: (context, _) {
        if (!widget.pwaInstallController.shouldShowBanner) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final width = MediaQuery.of(context).size.width;
        final isCompact = width < 720;

        final actions = Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _handleInstallPrompt,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Installieren'),
            ),
            TextButton(
              onPressed: widget.pwaInstallController.dismissBanner,
              child: const Text('Spaeter'),
            ),
          ],
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: isCompact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBannerHeader(theme),
                        const SizedBox(height: 16),
                        actions,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: _buildBannerHeader(theme)),
                        const SizedBox(width: 24),
                        actions,
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBannerHeader(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.install_desktop_rounded,
          color: theme.colorScheme.onPrimaryContainer,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GATED als Web-App installieren',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Fuege GATED deinem Home Screen oder Startmenue hinzu und starte die App kuenftig direkt im Standalone-Modus.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleInstallPrompt() async {
    final result = await widget.pwaInstallController.promptInstall();
    if (!mounted) {
      return;
    }

    showAppSnackBar(
      context,
      message: switch (result) {
        PwaInstallPromptResult.installed => 'Installationsdialog gestartet.',
        PwaInstallPromptResult.dismissed =>
          'Die Installation wurde abgebrochen.',
        PwaInstallPromptResult.unavailable =>
          (widget.pwaInstallController.statusMessage ??
              'Installation derzeit nicht verfuegbar.'),
        PwaInstallPromptResult.unsupported =>
          'Installations-Flow in diesem Browser nicht unterstuetzt.',
        PwaInstallPromptResult.error =>
          'Die Installation konnte nicht gestartet werden.',
      },
      withCloseAction: true,
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.selectedIndex, required this.children});

  final int selectedIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var index = 0; index < children.length; index++)
          Offstage(
            offstage: selectedIndex != index,
            child: TickerMode(
              enabled: selectedIndex == index,
              child: _ScrollableHomeView(child: children[index]),
            ),
          ),
      ],
    );
  }
}

class _ScrollableHomeView extends StatelessWidget {
  const _ScrollableHomeView({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: SizedBox(width: double.infinity, child: child),
          ),
        );
      },
    );
  }
}
