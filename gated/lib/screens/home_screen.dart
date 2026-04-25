import 'dart:async';

import 'package:flutter/material.dart';

import '../features/navbar/navbar.dart';
import '../features/pwa/pwa_install_controller.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';
import '../services/email_draft_service.dart';
import '../utils/snackbar_utils.dart';
import '../views/admin_view.dart';
import '../views/dashboard_view.dart';
import '../views/kennzeichen_view.dart';
import '../views/profile_view.dart';
import '../views/settings_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onThemeModeChanged,
    required this.pwaInstallController,
    AuthService? authService,
    AdminService? adminService,
    EmailDraftService? emailDraftService,
    Widget Function(bool isActive)? dashboardViewBuilder,
    Widget Function(bool isActive)? kennzeichenViewBuilder,
    Widget? profileView,
    Widget? settingsView,
  }) : _authService = authService,
       _adminService = adminService,
       _emailDraftService = emailDraftService,
       _dashboardViewBuilder = dashboardViewBuilder,
       _kennzeichenViewBuilder = kennzeichenViewBuilder,
       _profileView = profileView,
       _settingsView = settingsView;

  final ValueChanged<ThemeMode> onThemeModeChanged;
  final PwaInstallController pwaInstallController;
  final AuthService? _authService;
  final AdminService? _adminService;
  final EmailDraftService? _emailDraftService;
  final Widget Function(bool isActive)? _dashboardViewBuilder;
  final Widget Function(bool isActive)? _kennzeichenViewBuilder;
  final Widget? _profileView;
  final Widget? _settingsView;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AuthService _authService;
  late final AdminService _adminService;
  late final EmailDraftService _emailDraftService;
  int _selectedIndex = 0;
  AuthUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _authService = widget._authService ?? const AuthService();
    _adminService =
        widget._adminService ?? AdminService(authService: _authService);
    _emailDraftService = widget._emailDraftService ?? const EmailDraftService();
    _currentUser = _authService.cachedCurrentUser;
    unawaited(_loadCurrentUser());
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isPhone = width < 500;
    final banner = _buildInstallBanner(context);
    final navItems = _navItems;
    final currentSelectedIndex = _selectedIndex >= navItems.length
        ? navItems.length - 1
        : _selectedIndex;
    final children = _buildChildren(currentSelectedIndex);

    final content = _HomeContent(
      selectedIndex: currentSelectedIndex,
      children: children,
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
                  items: navItems,
                  selectedIndex: currentSelectedIndex,
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
                selectedIndex: currentSelectedIndex,
                onDestinationSelected: _onNavTap,
                destinations: [
                  for (final item in navItems)
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

  Future<void> _loadCurrentUser() async {
    try {
      final user = await _authService.getCurrentUser();
      if (!mounted) {
        return;
      }

      setState(() {
        _currentUser = user;
        if (_selectedIndex >= _buildChildrenCount(user)) {
          _selectedIndex = _buildChildrenCount(user) - 1;
        }
      });
    } catch (_) {
      // Navigation falls back to the non-admin tabs if the profile is unavailable.
    }
  }

  List<({String label, IconData icon})> get _navItems {
    final items = <({String label, IconData icon})>[
      (label: 'Dashboard', icon: Icons.dashboard_rounded),
      (label: 'Kennzeichen', icon: Icons.view_list_rounded),
      (label: 'Profil', icon: Icons.person_rounded),
    ];

    if (_currentUser?.role == AuthUserRole.admin) {
      items.add((label: 'Admin', icon: Icons.admin_panel_settings_rounded));
    }

    items.add((label: 'Einstellungen', icon: Icons.settings_rounded));
    return items;
  }

  List<Widget> _buildChildren(int selectedIndex) {
    final children = <Widget>[
      widget._dashboardViewBuilder?.call(selectedIndex == 0) ??
          DashboardView(
            key: const ValueKey('dashboard-view'),
            isActive: selectedIndex == 0,
          ),
      widget._kennzeichenViewBuilder?.call(selectedIndex == 1) ??
          KennzeichenView(
            key: const ValueKey('kennzeichen-view'),
            isActive: selectedIndex == 1,
          ),
      widget._profileView ?? const ProfileView(key: ValueKey('profile-view')),
    ];

    if (_currentUser?.role == AuthUserRole.admin) {
      children.add(
        AdminView(
          key: const ValueKey('admin-view'),
          adminService: _adminService,
          emailDraftService: _emailDraftService,
          authService: _authService,
          isActive: selectedIndex == 3,
        ),
      );
    }

    children.add(
      widget._settingsView ??
          SettingsView(
            key: const ValueKey('settings-view'),
            onThemeModeChanged: widget.onThemeModeChanged,
            pwaInstallController: widget.pwaInstallController,
          ),
    );

    return children;
  }

  int _buildChildrenCount(AuthUser user) {
    return user.role == AuthUserRole.admin ? 5 : 4;
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
