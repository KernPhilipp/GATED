import 'package:flutter/foundation.dart';

import 'pwa_install_state.dart';
import 'pwa_install_controller_stub.dart'
    if (dart.library.html) 'pwa_install_controller_web.dart'
    as impl;

abstract class PwaInstallController extends ChangeNotifier {
  PwaInstallController.internal();

  factory PwaInstallController() = impl.PwaInstallControllerImpl;

  PwaInstallState get state;
  bool get canPrompt;
  bool get isInstalled;
  bool get isSupportedBrowser;
  bool get isBannerDismissed;
  bool get shouldShowBanner;
  String? get statusMessage;

  Future<bool> promptInstall();
  void dismissBanner();
}
