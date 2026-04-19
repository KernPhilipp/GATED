import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'pwa_install_controller.dart';
import 'pwa_install_state.dart';

extension type BeforeInstallPromptEvent._(JSObject _)
    implements web.Event, JSObject {
  external JSPromise<PromptChoiceResult> prompt();
  external JSPromise<PromptChoiceResult> get userChoice;
}

extension type PromptChoiceResult._(JSObject _) implements JSObject {
  external JSString get outcome;
}

class PwaInstallControllerImpl extends PwaInstallController {
  PwaInstallControllerImpl() : super.internal() {
    _isSupportedBrowser = _detectSupportedBrowser();
    _state = _initialState();
    _beforeInstallListener = _handleBeforeInstallPrompt.toJS;
    _appInstalledListener = _handleAppInstalled.toJS;

    web.window.addEventListener('beforeinstallprompt', _beforeInstallListener);
    web.window.addEventListener('appinstalled', _appInstalledListener);
  }

  late final bool _isSupportedBrowser;
  late final JSExportedDartFunction _beforeInstallListener;
  late final JSExportedDartFunction _appInstalledListener;

  BeforeInstallPromptEvent? _deferredPromptEvent;
  bool _bannerDismissed = false;
  PwaInstallState _state = PwaInstallState.unsupported;

  @override
  PwaInstallState get state => _state;

  @override
  bool get canPrompt =>
      _isSupportedBrowser &&
      _state == PwaInstallState.available &&
      _deferredPromptEvent != null;

  @override
  bool get isInstalled => _state == PwaInstallState.installed;

  @override
  bool get isSupportedBrowser => _isSupportedBrowser;

  @override
  bool get isBannerDismissed => _bannerDismissed;

  @override
  bool get shouldShowBanner => canPrompt && !_bannerDismissed;

  @override
  String? get statusMessage {
    return switch (_state) {
      PwaInstallState.available => 'GATED kann als Web-App installiert werden.',
      PwaInstallState.installed => 'GATED ist bereits als Web-App installiert.',
      PwaInstallState.unavailableYet =>
        'Die Installation ist in Chrome oder Edge moeglich, sobald der Browser GATED als installierbar erkannt hat.',
      PwaInstallState.unsupported =>
        'Installations-Flow in diesem Browser nicht unterstuetzt.',
    };
  }

  @override
  void dismissBanner() {
    if (_bannerDismissed) {
      return;
    }

    _bannerDismissed = true;
    notifyListeners();
  }

  @override
  Future<bool> promptInstall() async {
    if (!canPrompt) {
      return false;
    }

    final promptEvent = _deferredPromptEvent;
    if (promptEvent == null) {
      return false;
    }

    try {
      await promptEvent.prompt().toDart;
      final choice = await promptEvent.userChoice.toDart;
      final outcome = choice.outcome.toDart;
      _clearPromptAvailability();
      return outcome == 'accepted';
    } catch (_) {
      _clearPromptAvailability();
      return false;
    }
  }

  @override
  void dispose() {
    web.window.removeEventListener(
      'beforeinstallprompt',
      _beforeInstallListener,
    );
    web.window.removeEventListener('appinstalled', _appInstalledListener);
    super.dispose();
  }

  bool _detectSupportedBrowser() {
    final userAgent = web.window.navigator.userAgent.toLowerCase();
    final platform = web.window.navigator.platform.toLowerCase();
    final maxTouchPoints = web.window.navigator.maxTouchPoints;

    final isIosDevice =
        userAgent.contains('iphone') ||
        userAgent.contains('ipad') ||
        userAgent.contains('ipod') ||
        (platform.contains('mac') && maxTouchPoints > 1);
    if (isIosDevice) {
      return false;
    }

    final isChromiumFamily =
        userAgent.contains('chrome') ||
        userAgent.contains('chromium') ||
        userAgent.contains('edg/') ||
        userAgent.contains('opr/');
    final isFirefox = userAgent.contains('firefox');
    final isSafariOnly =
        userAgent.contains('safari') &&
        !userAgent.contains('chrome') &&
        !userAgent.contains('chromium') &&
        !userAgent.contains('edg/') &&
        !userAgent.contains('opr/');

    return isChromiumFamily && !isFirefox && !isSafariOnly;
  }

  PwaInstallState _initialState() {
    if (!_isSupportedBrowser) {
      return PwaInstallState.unsupported;
    }

    if (_isRunningInstalled()) {
      _bannerDismissed = true;
      return PwaInstallState.installed;
    }

    return PwaInstallState.unavailableYet;
  }

  bool _isRunningInstalled() {
    final standalone = web.window.matchMedia('(display-mode: standalone)');
    final fullscreen = web.window.matchMedia('(display-mode: fullscreen)');
    final minimalUi = web.window.matchMedia('(display-mode: minimal-ui)');
    final referrer = web.document.referrer;

    return standalone.matches ||
        fullscreen.matches ||
        minimalUi.matches ||
        referrer.startsWith('android-app://');
  }

  void _handleBeforeInstallPrompt(web.Event event) {
    event.preventDefault();
    _deferredPromptEvent = event as BeforeInstallPromptEvent;
    _updateState(PwaInstallState.available);
  }

  void _handleAppInstalled(web.Event _) {
    _deferredPromptEvent = null;
    _bannerDismissed = true;
    _updateState(PwaInstallState.installed);
  }

  void _clearPromptAvailability() {
    _deferredPromptEvent = null;
    if (_state == PwaInstallState.installed) {
      return;
    }

    _updateState(PwaInstallState.unavailableYet);
  }

  void _updateState(PwaInstallState nextState) {
    if (_state == nextState) {
      notifyListeners();
      return;
    }

    _state = nextState;
    notifyListeners();
  }
}
