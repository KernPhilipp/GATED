import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gated/features/pwa/pwa_install_controller.dart';
import 'package:gated/features/pwa/pwa_install_state.dart';
import 'package:gated/screens/home_screen.dart';
import 'package:gated/services/admin_service.dart';
import 'package:gated/services/auth_service.dart';
import 'package:gated/services/email_draft_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('admin tab is hidden for non-admin users', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          onThemeModeChanged: (_) {},
          pwaInstallController: _FakePwaInstallController(),
          authService: _FakeAuthService(
            user: AuthUser(
              id: 1,
              email: 'user@example.com',
              role: AuthUserRole.user,
              createdAt: DateTime.utc(2026, 4, 24),
            ),
          ),
          adminService: _FakeAdminService(),
          emailDraftService: _FakeEmailDraftService(),
          dashboardViewBuilder: (_) => const SizedBox.shrink(),
          kennzeichenViewBuilder: (_) => const SizedBox.shrink(),
          profileView: const SizedBox.shrink(),
          settingsView: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.admin_panel_settings_rounded), findsNothing);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('admin table disables actions for admin rows', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          onThemeModeChanged: (_) {},
          pwaInstallController: _FakePwaInstallController(),
          authService: _FakeAuthService(
            user: AuthUser(
              id: 1,
              email: 'admin@example.com',
              role: AuthUserRole.admin,
              createdAt: DateTime.utc(2026, 4, 24),
            ),
          ),
          adminService: _FakeAdminService(
            users: const [
              AdminUser(
                id: 1,
                email: 'admin@example.com',
                role: AuthUserRole.admin,
                createdAt: null,
              ),
              AdminUser(
                id: 2,
                email: 'user@example.com',
                role: AuthUserRole.user,
                createdAt: null,
              ),
            ],
          ),
          emailDraftService: _FakeEmailDraftService(),
          dashboardViewBuilder: (_) => const SizedBox.shrink(),
          kennzeichenViewBuilder: (_) => const SizedBox.shrink(),
          profileView: const SizedBox.shrink(),
          settingsView: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.admin_panel_settings_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.admin_panel_settings_rounded));
    await tester.pumpAndSettle();

    final resetButtons = tester
        .widgetList<IconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is IconButton &&
                widget.icon is Icon &&
                (widget.icon as Icon).icon == Icons.mail_outline_rounded,
          ),
        )
        .toList();
    final deleteButtons = tester
        .widgetList<IconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is IconButton &&
                widget.icon is Icon &&
                (widget.icon as Icon).icon == Icons.delete_outline_rounded,
          ),
        )
        .toList();

    expect(resetButtons, hasLength(2));
    expect(deleteButtons, hasLength(2));
    expect(resetButtons.first.onPressed, isNull);
    expect(deleteButtons.first.onPressed, isNull);
    expect(resetButtons.last.onPressed, isNotNull);
    expect(deleteButtons.last.onPressed, isNotNull);
    await tester.binding.setSurfaceSize(null);
  });
}

class _FakeAuthService extends AuthService {
  _FakeAuthService({required this.user}) : super(baseUrl: 'http://localhost');

  final AuthUser user;

  @override
  AuthUser? get cachedCurrentUser => user;

  @override
  Future<AuthUser> getCurrentUser() async => user;

  @override
  Future<void> prefetchCurrentUser() async {}
}

class _FakeAdminService extends AdminService {
  _FakeAdminService({this.users = const []})
    : super(authService: AuthService(baseUrl: 'http://localhost'));

  final List<AdminUser> users;

  @override
  Future<List<AdminUser>> fetchUsers() async => users;
}

class _FakeEmailDraftService extends EmailDraftService {}

class _FakePwaInstallController extends PwaInstallController {
  _FakePwaInstallController() : super.internal();

  @override
  bool get canPrompt => false;

  @override
  bool get isBannerDismissed => true;

  @override
  bool get isInstalled => false;

  @override
  bool get isSupportedBrowser => false;

  @override
  PwaInstallState get state => PwaInstallState.unsupported;

  @override
  String? get statusMessage => null;

  @override
  bool get shouldShowBanner => false;

  @override
  void dismissBanner() {}

  @override
  Future<PwaInstallPromptResult> promptInstall() async {
    return PwaInstallPromptResult.unsupported;
  }
}
