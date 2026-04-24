import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gated/features/pwa/pwa_install_controller.dart';
import 'package:gated/features/pwa/pwa_install_state.dart';
import 'package:gated/services/app_metadata_service.dart';
import 'package:gated/views/settings_view.dart';

void main() {
  testWidgets('about dialog shows the runtime app version', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsView(
            onThemeModeChanged: (_) {},
            pwaInstallController: _FakePwaInstallController(),
            appMetadataService: _FakeAppMetadataService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('GATED'));
    await tester.pumpAndSettle();

    expect(find.text('2.5.7+19'), findsOneWidget);
  });
}

class _FakeAppMetadataService extends AppMetadataService {
  @override
  Future<String> loadAppVersion() async => '2.5.7+19';
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
