import 'package:flutter_test/flutter_test.dart';
import 'package:gated/app/app.dart';
import 'package:gated/features/pwa/pwa_install_controller.dart';
import 'package:gated/features/pwa/pwa_install_state.dart';
import 'package:gated/services/auth_service.dart';

void main() {
  testWidgets(
    'stored credentials still keep the app on login when restore fails',
    (tester) async {
      await tester.pumpWidget(
        GatedApp(
          authService: _ThrowingAuthService(),
          pwaInstallController: _FakePwaInstallController(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Login'), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
    },
  );
}

class _ThrowingAuthService extends AuthService {
  _ThrowingAuthService() : super(baseUrl: 'http://localhost');

  @override
  Future<bool> restoreSession() async {
    throw const AuthException('Backend offline');
  }
}

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
