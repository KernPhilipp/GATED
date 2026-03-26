import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.createdAt,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final createdAtValue = json['createdAt'];
    final createdAt = createdAtValue is String && createdAtValue.isNotEmpty
        ? DateTime.tryParse(createdAtValue.replaceFirst(' ', 'T'))
        : null;

    return AuthUser(
      id: json['uid'] as int,
      email: json['email'] as String,
      createdAt: createdAt,
    );
  }

  final int id;
  final String email;
  final DateTime? createdAt;
}

class AuthService {
  const AuthService({this.baseUrl = AppConfig.apiBaseUrl});

  final String baseUrl;
  static AuthUser? _cachedCurrentUser;
  static Future<AuthUser>? _currentUserRequest;
  static int _currentUserCacheVersion = 0;
  static final Future<SharedPreferencesWithCache> _prefs =
      SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(
          allowList: <String>{_tokenKey},
        ),
      );

  AuthUser? get cachedCurrentUser => _cachedCurrentUser;

  Future<String> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_normalizedBaseUrl/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final token = data['token'];
      if (token is! String || token.isEmpty) {
        throw const AuthException('Ungültige Server-Antwort.');
      }
      await _saveToken(token);
      return token;
    }

    if (response.statusCode == 403) {
      throw const AuthException('E-Mail oder Passwort ist falsch.');
    }

    if (response.statusCode == 400) {
      throw const AuthException('Bitte E-Mail und Passwort eingeben.');
    }

    if (response.statusCode == 500) {
      throw const AuthException('Serverfehler. Bitte später versuchen.');
    }

    throw const AuthException('Server-Fehler. Bitte später versuchen.');
  }

  Future<void> register({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_normalizedBaseUrl/auth/register'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      return;
    }

    if (response.statusCode == 400) {
      throw const AuthException('Bitte E-Mail und Passwort eingeben.');
    }

    if (response.statusCode == 403) {
      throw const AuthException('E-Mail ist nicht erlaubt.');
    }

    if (response.statusCode == 409) {
      throw const AuthException('User existiert bereits.');
    }

    if (response.statusCode == 500) {
      throw const AuthException('Serverfehler. Bitte später versuchen.');
    }

    throw const AuthException('Server-Fehler. Bitte später versuchen.');
  }

  Future<AuthUser> getCurrentUser() async {
    final cachedUser = _cachedCurrentUser;
    if (cachedUser != null) {
      return cachedUser;
    }

    final currentUserRequest = _currentUserRequest;
    if (currentUserRequest != null) {
      return currentUserRequest;
    }

    return _startCurrentUserRequest();
  }

  Future<AuthUser> refreshCurrentUser() async {
    _cachedCurrentUser = null;

    final currentUserRequest = _currentUserRequest;
    if (currentUserRequest != null) {
      return currentUserRequest;
    }

    return _startCurrentUserRequest();
  }

  Future<void> prefetchCurrentUser() async {
    try {
      await getCurrentUser();
    } catch (_) {
      // Prefetch should not interrupt navigation.
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$_normalizedBaseUrl/auth/change-password'),
      headers: await _authorizedHeaders(includeJsonContentType: true),
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );

    if (response.statusCode == 200) {
      return;
    }

    if (response.statusCode == 400) {
      throw const AuthException('Bitte aktuelles und neues Passwort eingeben.');
    }

    if (response.statusCode == 403) {
      if (isTokenErrorResponse(response.body)) {
        await clearToken();
        throw const SessionExpiredException();
      }
      throw const AuthException('Aktuelles Passwort ist falsch.');
    }

    if (response.statusCode == 409) {
      throw const AuthException(
        'Das neue Passwort muss sich vom aktuellen unterscheiden.',
      );
    }

    if (response.statusCode == 500) {
      throw const AuthException('Serverfehler. Bitte später versuchen.');
    }

    throw const AuthException('Passwort konnte nicht geändert werden.');
  }

  Future<AuthUser> _startCurrentUserRequest() {
    final requestVersion = _currentUserCacheVersion;
    final completer = Completer<AuthUser>();
    _currentUserRequest = completer.future;

    () async {
      try {
        final user = await _fetchCurrentUser(requestVersion);
        completer.complete(user);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _currentUserRequest = null;
      }
    }();

    return completer.future;
  }

  Future<AuthUser> _fetchCurrentUser(int requestVersion) async {
    final response = await http.get(
      Uri.parse('$_normalizedBaseUrl/auth/me'),
      headers: await _authorizedHeaders(),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        throw const AuthException('Ungültige Server-Antwort.');
      }

      final user = AuthUser.fromJson(data);
      if (requestVersion == _currentUserCacheVersion) {
        _cachedCurrentUser = user;
      }
      return user;
    }

    if (response.statusCode == 403 && isTokenErrorResponse(response.body)) {
      await clearToken();
      throw const SessionExpiredException();
    }

    if (response.statusCode == 500) {
      throw const AuthException('Serverfehler. Bitte später versuchen.');
    }

    throw const AuthException('Profil konnte nicht geladen werden.');
  }

  Future<void> _saveToken(String token) async {
    final prefs = await _prefs;
    _clearCachedCurrentUser();
    await prefs.setString(_tokenKey, token);
  }

  Future<String?> readToken() async {
    final prefs = await _prefs;
    return prefs.getString(_tokenKey);
  }

  Future<void> clearToken() async {
    final prefs = await _prefs;
    _clearCachedCurrentUser();
    await prefs.remove(_tokenKey);
  }

  Future<Map<String, String>> authorizedHeaders({
    bool includeJsonContentType = false,
  }) {
    return _authorizedHeaders(includeJsonContentType: includeJsonContentType);
  }

  void _clearCachedCurrentUser() {
    _cachedCurrentUser = null;
    _currentUserRequest = null;
    _currentUserCacheVersion++;
  }

  Future<Map<String, String>> _authorizedHeaders({
    bool includeJsonContentType = false,
  }) async {
    final token = await readToken();
    if (token == null || token.isEmpty) {
      throw const SessionExpiredException();
    }

    return {
      if (includeJsonContentType) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  String get _normalizedBaseUrl => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;
}

class SessionExpiredException extends AuthException {
  const SessionExpiredException([
    super.message = 'Sitzung abgelaufen. Bitte erneut anmelden.',
  ]);
}

bool isTokenErrorResponse(String responseBody) {
  final normalized = responseBody.trim().toLowerCase();
  return normalized == 'no token' ||
      normalized == 'token expired' ||
      normalized == 'invalid token' ||
      normalized == 'user not found';
}

const _tokenKey = 'auth_token';
