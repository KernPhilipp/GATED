import 'auth_token_store_shared.dart'
    if (dart.library.html) 'auth_token_store_web.dart'
    as impl;

const authAccessTokenKey = 'auth_access_token';
const authRefreshTokenKey = 'auth_refresh_token';

abstract class AuthTokenStore {
  const AuthTokenStore();

  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

AuthTokenStore createAuthTokenStore() => impl.AuthTokenStoreImpl();
