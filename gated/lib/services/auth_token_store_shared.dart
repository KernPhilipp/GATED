import 'package:shared_preferences/shared_preferences.dart';

import 'auth_token_store.dart';

class AuthTokenStoreImpl implements AuthTokenStore {
  AuthTokenStoreImpl();

  static final Future<SharedPreferencesWithCache> _prefs =
      SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(
          allowList: <String>{authAccessTokenKey, authRefreshTokenKey},
        ),
      );

  @override
  Future<String?> read(String key) async {
    final prefs = await _prefs;
    return prefs.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    final prefs = await _prefs;
    await prefs.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    final prefs = await _prefs;
    await prefs.remove(key);
  }
}
