import 'dart:async';

import 'package:flutter/material.dart';

import '../features/navbar/navbar.dart';
import '../services/auth_service.dart';
import '../views/kennzeichen_view.dart';
import '../views/profile_view.dart';
import '../views/settings_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onThemeModeChanged});

  final ValueChanged<ThemeMode> onThemeModeChanged;

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
    final views = <Widget>[
      const Placeholder(key: ValueKey('dashboard-view')),
      const KennzeichenView(key: ValueKey('kennzeichen-view')),
      const ProfileView(key: ValueKey('profile-view')),
      SettingsView(onThemeModeChanged: widget.onThemeModeChanged),
    ];

    final content = LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: views[_selectedIndex],
          ),
        );
      },
    );

    return Scaffold(
      body: isPhone
          ? content
          : Row(
              children: [
                NavigationSidebar(
                  items: _navItems,
                  selectedIndex: _selectedIndex,
                  onTap: _onNavTap,
                ),
                Expanded(child: content),
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
}
