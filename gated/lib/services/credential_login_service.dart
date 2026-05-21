import 'credential_login_service_stub.dart'
    if (dart.library.html) 'credential_login_service_web.dart'
    as impl;

enum CredentialLoginStatus { success, unsupported, empty, cancelled, error }

class CredentialLoginResult {
  const CredentialLoginResult._({
    required this.status,
    this.email,
    this.password,
  });

  const CredentialLoginResult.success({
    required String email,
    required String password,
  }) : this._(
         status: CredentialLoginStatus.success,
         email: email,
         password: password,
       );

  const CredentialLoginResult.unsupported()
    : this._(status: CredentialLoginStatus.unsupported);

  const CredentialLoginResult.empty()
    : this._(status: CredentialLoginStatus.empty);

  const CredentialLoginResult.cancelled()
    : this._(status: CredentialLoginStatus.cancelled);

  const CredentialLoginResult.error()
    : this._(status: CredentialLoginStatus.error);

  final CredentialLoginStatus status;
  final String? email;
  final String? password;

  bool get hasCredential =>
      status == CredentialLoginStatus.success &&
      email != null &&
      password != null;
}

abstract class CredentialLoginService {
  const CredentialLoginService.internal();

  factory CredentialLoginService() = impl.CredentialLoginServiceImpl;

  Future<CredentialLoginResult> getPasswordCredential();

  Future<void> storePasswordCredential({
    required String email,
    required String password,
  });
}
