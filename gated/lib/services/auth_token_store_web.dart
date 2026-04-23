import 'package:web/web.dart' as web;

import 'auth_token_store.dart';

class AuthTokenStoreImpl implements AuthTokenStore {
  AuthTokenStoreImpl();

  static final Map<String, String> _memoryFallback = <String, String>{};

  @override
  Future<String?> read(String key) async {
    try {
      return web.window.sessionStorage.getItem(key) ?? _memoryFallback[key];
    } catch (_) {
      return _memoryFallback[key];
    }
  }

  @override
  Future<void> write(String key, String value) async {
    _memoryFallback[key] = value;
    try {
      web.window.sessionStorage.setItem(key, value);
    } catch (_) {
      // sessionStorage may be unavailable in private or restricted contexts.
    }
  }

  @override
  Future<void> remove(String key) async {
    _memoryFallback.remove(key);
    try {
      web.window.sessionStorage.removeItem(key);
    } catch (_) {
      // sessionStorage may be unavailable in private or restricted contexts.
    }
  }
}
