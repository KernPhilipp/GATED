import 'credential_login_service.dart';

class CredentialLoginServiceImpl extends CredentialLoginService {
  const CredentialLoginServiceImpl() : super.internal();

  @override
  Future<CredentialLoginResult> getPasswordCredential() async {
    return const CredentialLoginResult.unsupported();
  }

  @override
  Future<void> storePasswordCredential({
    required String email,
    required String password,
  }) async {}
}
