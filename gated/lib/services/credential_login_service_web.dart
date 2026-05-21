import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'credential_login_service.dart';

extension type _PasswordCredential._(JSObject _)
    implements web.Credential, JSObject {
  external String get password;
}

class CredentialLoginServiceImpl extends CredentialLoginService {
  const CredentialLoginServiceImpl() : super.internal();

  @override
  Future<CredentialLoginResult> getPasswordCredential() async {
    if (!_hasCredentialApi) {
      return const CredentialLoginResult.unsupported();
    }

    final stopwatch = Stopwatch()..start();
    try {
      final credential = await web.window.navigator.credentials
          .get(web.CredentialRequestOptions(password: true))
          .toDart;
      stopwatch.stop();

      if (credential == null) {
        return _resultForMissingCredential(stopwatch.elapsed);
      }

      if (credential.type != 'password') {
        return const CredentialLoginResult.empty();
      }

      final email = credential.id.trim();
      final password = _PasswordCredential._(credential).password;
      if (email.isEmpty || password.isEmpty) {
        return const CredentialLoginResult.empty();
      }

      return CredentialLoginResult.success(email: email, password: password);
    } catch (error) {
      return _isCancelled(error)
          ? const CredentialLoginResult.cancelled()
          : const CredentialLoginResult.error();
    }
  }

  @override
  Future<void> storePasswordCredential({
    required String email,
    required String password,
  }) async {
    if (!_hasCredentialApi || email.trim().isEmpty || password.isEmpty) {
      return;
    }

    try {
      final credential = await web.window.navigator.credentials
          .create(
            web.CredentialCreationOptions(
              password: web.PasswordCredentialData(
                id: email.trim(),
                password: password,
                origin: web.window.location.origin,
              ),
            ),
          )
          .toDart;

      if (credential == null) {
        return;
      }

      await web.window.navigator.credentials.store(credential).toDart;
    } catch (_) {
      // Credential storage is best-effort and must never affect auth flow.
    }
  }

  bool get _hasCredentialApi {
    return web.window.navigator.hasProperty('credentials'.toJS).toDart;
  }

  bool _isCancelled(Object error) {
    final message = error.toString();
    return message.contains('NotAllowedError') ||
        message.contains('AbortError');
  }

  CredentialLoginResult _resultForMissingCredential(Duration elapsed) {
    const cancellationThreshold = Duration(milliseconds: 500);
    if (elapsed >= cancellationThreshold) {
      return const CredentialLoginResult.cancelled();
    }

    return const CredentialLoginResult.empty();
  }
}
