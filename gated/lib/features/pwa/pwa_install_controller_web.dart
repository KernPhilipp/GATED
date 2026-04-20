import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'pwa_install_controller.dart';
import 'pwa_install_state.dart';

const _persistedInstallKey = 'gated_pwa_installed';
const _manifestId = './';
const _manifestPathSuffix = '/manifest.json';

extension type BeforeInstallPromptEvent._(JSObject _)
    implements web.Event, JSObject {
  external JSPromise<PromptChoiceResult> prompt();
  external JSPromise<PromptChoiceResult> get userChoice;
}

extension type PromptChoiceResult._(JSObject _) implements JSObject {
  external JSString get outcome;
}

extension type RelatedApplication._(JSObject _) implements JSObject {
  external JSString? get platform;
  external JSString? get id;
  external JSString? get url;
}

extension NavigatorInstallRelatedAppsExtension on web.Navigator {
  external JSPromise<JSArray<RelatedApplication>> getInstalledRelatedApps();
}

class PwaInstallControllerImpl extends PwaInstallController {
  PwaInstallControllerImpl() : super.internal() {
    _isSupportedBrowser = _detectSupportedBrowser();
    _state = _initialState();
    _beforeInstallListener = _handleBeforeInstallPrompt.toJS;
    _appInstalledListener = _handleAppInstalled.toJS;

    web.window.addEventListener('beforeinstallprompt', _beforeInstallListener);
    web.window.addEventListener('appinstalled', _appInstalledListener);
    unawaited(_refreshInstalledState());
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
  Future<PwaInstallPromptResult> promptInstall() async {
    if (!_isSupportedBrowser) {
      return PwaInstallPromptResult.unsupported;
    }

    if (isInstalled) {
      return PwaInstallPromptResult.installed;
    }

    if (!canPrompt) {
      return PwaInstallPromptResult.unavailable;
    }

    final promptEvent = _deferredPromptEvent;
    if (promptEvent == null) {
      return PwaInstallPromptResult.unavailable;
    }

    try {
      await promptEvent.prompt().toDart;
      final choice = await promptEvent.userChoice.toDart;
      final outcome = choice.outcome.toDart;
      _clearPromptAvailability();
      return outcome == 'accepted'
          ? PwaInstallPromptResult.installed
          : PwaInstallPromptResult.dismissed;
    } catch (_) {
      _clearPromptAvailability();
      return PwaInstallPromptResult.error;
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

    if (_isRunningInstalled() || _readPersistedInstallFlag()) {
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
    _clearPersistedInstallFlag();
    _updateState(PwaInstallState.available);
  }

  void _handleAppInstalled(web.Event _) {
    _deferredPromptEvent = null;
    _bannerDismissed = true;
    _persistInstalledFlag();
    _updateState(PwaInstallState.installed);
  }

  void _clearPromptAvailability() {
    _deferredPromptEvent = null;
    if (_state == PwaInstallState.installed) {
      return;
    }

    _updateState(PwaInstallState.unavailableYet);
  }

  Future<void> _refreshInstalledState() async {
    if (!_isSupportedBrowser || _isRunningInstalled()) {
      return;
    }

    final relatedAppInstalled = await _isRelatedAppInstalled();
    if (!relatedAppInstalled) {
      return;
    }

    _bannerDismissed = true;
    _persistInstalledFlag();
    _updateState(PwaInstallState.installed);
  }

  Future<bool> _isRelatedAppInstalled() async {
    final navigator = web.window.navigator;
    if (!(navigator as JSObject).has('getInstalledRelatedApps')) {
      return false;
    }

    try {
      final installedApps = await navigator.getInstalledRelatedApps().toDart;
      for (final app in installedApps.toDart) {
        final platform = app.platform?.toDart.toLowerCase() ?? '';
        final id = app.id?.toDart ?? '';
        final url = app.url?.toDart ?? '';
        if (platform == 'webapp' &&
            (id == _manifestId || url.endsWith(_manifestPathSuffix))) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  bool _readPersistedInstallFlag() {
    try {
      return web.window.localStorage.getItem(_persistedInstallKey) == 'true';
    } catch (_) {
      return false;
    }
  }

  void _persistInstalledFlag() {
    try {
      web.window.localStorage.setItem(_persistedInstallKey, 'true');
    } catch (_) {
      // localStorage may be unavailable in private or restricted contexts.
    }
  }

  void _clearPersistedInstallFlag() {
    try {
      web.window.localStorage.removeItem(_persistedInstallKey);
    } catch (_) {
      // localStorage may be unavailable in private or restricted contexts.
    }
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
