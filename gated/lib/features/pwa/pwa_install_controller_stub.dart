import 'pwa_install_controller.dart';
import 'pwa_install_state.dart';

class PwaInstallControllerImpl extends PwaInstallController {
  PwaInstallControllerImpl() : super.internal();

  @override
  PwaInstallState get state => PwaInstallState.unsupported;

  @override
  bool get canPrompt => false;

  @override
  bool get isInstalled => false;

  @override
  bool get isSupportedBrowser => false;

  @override
  bool get isBannerDismissed => true;

  @override
  bool get shouldShowBanner => false;

  @override
  String? get statusMessage => null;

  @override
  void dismissBanner() {}

  @override
  Future<bool> promptInstall() async => false;
}
