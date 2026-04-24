import 'package:flutter/material.dart';
import '../features/pwa/pwa_install_controller.dart';
import '../services/auth_service.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/register_screen.dart';
import 'theme.dart';

class GatedApp extends StatefulWidget {
  const GatedApp({
    super.key,
    AuthService? authService,
    PwaInstallController? pwaInstallController,
  }) : _authService = authService,
       _pwaInstallController = pwaInstallController;

  final AuthService? _authService;
  final PwaInstallController? _pwaInstallController;

  @override
  State<GatedApp> createState() => _GatedAppState();
}

class _GatedAppState extends State<GatedApp> {
  late final AuthService _authService;
  late final PwaInstallController _pwaInstallController;
  ThemeMode _themeMode = ThemeMode.system;
  late final Future<String> _initialRoute;

  @override
  void initState() {
    super.initState();
    _authService = widget._authService ?? const AuthService();
    _pwaInstallController =
        widget._pwaInstallController ?? PwaInstallController();
    _initialRoute = _resolveInitialRoute();
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  Future<String> _resolveInitialRoute() async {
    try {
      final hasSession = await _authService.restoreSession();
      return hasSession ? '/home' : '/login';
    } on AuthException {
      return '/login';
    } catch (_) {
      return '/login';
    }
  }

  @override
  void dispose() {
    _pwaInstallController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GATED',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: _themeMode,
      home: FutureBuilder<String>(
        future: _initialRoute,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const _AppLaunchScreen();
          }

          return switch (snapshot.data) {
            '/home' => HomeScreen(
              onThemeModeChanged: _setThemeMode,
              pwaInstallController: _pwaInstallController,
            ),
            '/register' => const RegisterScreen(),
            _ => const LoginScreen(),
          };
        },
      ),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => HomeScreen(
          onThemeModeChanged: _setThemeMode,
          pwaInstallController: _pwaInstallController,
        ),
      },
    );
  }
}

class _AppLaunchScreen extends StatelessWidget {
  const _AppLaunchScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator.adaptive()),
    );
  }
}
