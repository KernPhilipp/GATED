import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/register_screen.dart';
import 'theme.dart';

class GatedApp extends StatefulWidget {
  const GatedApp({super.key});

  @override
  State<GatedApp> createState() => _GatedAppState();
}

class _GatedAppState extends State<GatedApp> {
  final _authService = const AuthService();
  ThemeMode _themeMode = ThemeMode.system;
  late final Future<String> _initialRoute = _resolveInitialRoute();

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  Future<String> _resolveInitialRoute() async {
    try {
      final hasSession = await _authService.restoreSession();
      return hasSession ? '/home' : '/login';
    } on AuthException {
      return '/home';
    } catch (_) {
      return '/home';
    }
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
            '/home' => HomeScreen(onThemeModeChanged: _setThemeMode),
            '/register' => const RegisterScreen(),
            _ => const LoginScreen(),
          };
        },
      ),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => HomeScreen(onThemeModeChanged: _setThemeMode),
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
