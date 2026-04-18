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
  const AuthService({this.baseUrl = AppConfig.apiBaseUrl, http.Client? client})
    : _client = client;

  final String baseUrl;
  final http.Client? _client;

  static AuthUser? _cachedCurrentUser;
  static Future<AuthUser>? _currentUserRequest;
  static int _currentUserCacheVersion = 0;
  static Future<bool>? _refreshRequest;
  static final http.Client _defaultClient = http.Client();
  static final Future<SharedPreferencesWithCache> _prefs =
      SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(
          allowList: <String>{_accessTokenKey, _refreshTokenKey},
        ),
      );

  AuthUser? get cachedCurrentUser => _cachedCurrentUser;

  Future<void> login({required String email, required String password}) async {
    final response = await _httpClient.post(
      Uri.parse('$_normalizedBaseUrl/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final tokens = _parseTokenPair(response.body);
      await _saveTokens(tokens);
      return;
    }

    if (response.statusCode == 403) {
      throw const AuthException('E-Mail oder Passwort ist falsch.');
    }

    if (response.statusCode == 400) {
      throw const AuthException('Bitte E-Mail und Passwort eingeben.');
    }

    if (response.statusCode == 500) {
      throw const AuthException('Serverfehler. Bitte spaeter versuchen.');
    }

    throw const AuthException('Server-Fehler. Bitte spaeter versuchen.');
  }

  Future<void> register({
    required String email,
    required String password,
  }) async {
    final response = await _httpClient.post(
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
      throw const AuthException('Serverfehler. Bitte spaeter versuchen.');
    }

    throw const AuthException('Server-Fehler. Bitte spaeter versuchen.');
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
    final response = await sendAuthorizedRequest(
      method: 'POST',
      path: '/auth/change-password',
      includeJsonContentType: true,
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );

    if (response.statusCode == 200) {
      await clearTokens();
      return;
    }

    if (response.statusCode == 400) {
      throw const AuthException('Bitte aktuelles und neues Passwort eingeben.');
    }

    if (response.statusCode == 403) {
      throw const AuthException('Aktuelles Passwort ist falsch.');
    }

    if (response.statusCode == 409) {
      throw const AuthException(
        'Das neue Passwort muss sich vom aktuellen unterscheiden.',
      );
    }

    if (response.statusCode == 500) {
      throw const AuthException('Serverfehler. Bitte spaeter versuchen.');
    }

    throw const AuthException('Passwort konnte nicht geaendert werden.');
  }

  Future<bool> restoreSession() async {
    final accessToken = await readAccessToken();
    final refreshToken = await readRefreshToken();
    final hasAccessToken = accessToken != null && accessToken.isNotEmpty;
    final hasRefreshToken = refreshToken != null && refreshToken.isNotEmpty;

    if (!hasAccessToken && !hasRefreshToken) {
      return false;
    }

    if (!hasAccessToken && hasRefreshToken) {
      final refreshed = await refreshSession();
      if (!refreshed) {
        return false;
      }
    }

    try {
      await getCurrentUser();
      return true;
    } on SessionExpiredException {
      await clearTokens();
      return false;
    } on AuthException {
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<void> logout() async {
    try {
      await sendAuthorizedRequest(method: 'POST', path: '/auth/logout');
    } on SessionExpiredException {
      // Local cleanup is still required if the backend session already expired.
    } finally {
      await clearTokens();
    }
  }

  Future<http.Response> sendAuthorizedRequest({
    required String method,
    required String path,
    String? body,
    bool includeJsonContentType = false,
  }) {
    return _sendAuthorizedRequest(
      method: method,
      path: path,
      body: body,
      includeJsonContentType: includeJsonContentType,
      allowRefreshRetry: true,
    );
  }

  Future<bool> refreshSession() async {
    final refreshRequest = _refreshRequest;
    if (refreshRequest != null) {
      return refreshRequest;
    }

    final completer = Completer<bool>();
    _refreshRequest = completer.future;

    () async {
      try {
        completer.complete(await _performRefresh());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _refreshRequest = null;
      }
    }();

    return completer.future;
  }

  Future<String?> readAccessToken() async {
    final prefs = await _prefs;
    return prefs.getString(_accessTokenKey);
  }

  Future<String?> readRefreshToken() async {
    final prefs = await _prefs;
    return prefs.getString(_refreshTokenKey);
  }

  Future<String?> readToken() => readAccessToken();

  Future<void> clearTokens() async {
    final prefs = await _prefs;
    _clearCachedCurrentUser();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
  }

  Future<void> clearToken() => clearTokens();

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
    final response = await sendAuthorizedRequest(
      method: 'GET',
      path: '/auth/me',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        throw const AuthException('Ungueltige Server-Antwort.');
      }

      final user = AuthUser.fromJson(data);
      if (requestVersion == _currentUserCacheVersion) {
        _cachedCurrentUser = user;
      }
      return user;
    }

    if (response.statusCode == 500) {
      throw const AuthException('Serverfehler. Bitte spaeter versuchen.');
    }

    throw const AuthException('Profil konnte nicht geladen werden.');
  }

  Future<http.Response> _sendAuthorizedRequest({
    required String method,
    required String path,
    required bool allowRefreshRetry,
    String? body,
    bool includeJsonContentType = false,
  }) async {
    final accessToken = await _requireAccessToken();
    final response = await _sendRequest(
      method: method,
      uri: Uri.parse('$_normalizedBaseUrl$path'),
      headers: {
        if (includeJsonContentType) 'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: body,
    );

    if (allowRefreshRetry &&
        response.statusCode == 403 &&
        isAccessTokenExpiredResponse(response.body)) {
      final refreshed = await refreshSession();
      if (!refreshed) {
        throw const SessionExpiredException();
      }

      return _sendAuthorizedRequest(
        method: method,
        path: path,
        body: body,
        includeJsonContentType: includeJsonContentType,
        allowRefreshRetry: false,
      );
    }

    if (response.statusCode == 403 && isSessionFailureResponse(response.body)) {
      await clearTokens();
      throw const SessionExpiredException();
    }

    return response;
  }

  Future<String> _requireAccessToken() async {
    final accessToken = await readAccessToken();
    if (accessToken != null && accessToken.isNotEmpty) {
      return accessToken;
    }

    final refreshed = await refreshSession();
    if (!refreshed) {
      throw const SessionExpiredException();
    }

    final refreshedAccessToken = await readAccessToken();
    if (refreshedAccessToken == null || refreshedAccessToken.isEmpty) {
      throw const SessionExpiredException();
    }

    return refreshedAccessToken;
  }

  Future<bool> _performRefresh() async {
    final refreshToken = await readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await clearTokens();
      return false;
    }

    final response = await _httpClient.post(
      Uri.parse('$_normalizedBaseUrl/auth/refresh'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );

    if (response.statusCode == 200) {
      final tokens = _parseTokenPair(response.body);
      await _saveTokens(tokens);
      return true;
    }

    await clearTokens();
    return false;
  }

  Future<void> _saveTokens(_TokenPair tokens) async {
    final prefs = await _prefs;
    _clearCachedCurrentUser();
    await prefs.setString(_accessTokenKey, tokens.accessToken);
    await prefs.setString(_refreshTokenKey, tokens.refreshToken);
  }

  void _clearCachedCurrentUser() {
    _cachedCurrentUser = null;
    _currentUserRequest = null;
    _currentUserCacheVersion++;
  }

  Future<http.Response> _sendRequest({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) {
    switch (method.toUpperCase()) {
      case 'GET':
        return _httpClient.get(uri, headers: headers);
      case 'POST':
        return _httpClient.post(uri, headers: headers, body: body);
      case 'PUT':
        return _httpClient.put(uri, headers: headers, body: body);
      case 'DELETE':
        return _httpClient.delete(uri, headers: headers, body: body);
      default:
        throw ArgumentError.value(method, 'method', 'Unsupported HTTP method');
    }
  }

  String get _normalizedBaseUrl => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  http.Client get _httpClient => _client ?? _defaultClient;
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

class _TokenPair {
  const _TokenPair({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

_TokenPair _parseTokenPair(String responseBody) {
  final decoded = jsonDecode(responseBody);
  if (decoded is! Map<String, dynamic>) {
    throw const AuthException('Ungueltige Server-Antwort.');
  }

  final accessToken = decoded['accessToken'];
  final refreshToken = decoded['refreshToken'];
  if (accessToken is! String ||
      accessToken.isEmpty ||
      refreshToken is! String ||
      refreshToken.isEmpty) {
    throw const AuthException('Ungueltige Server-Antwort.');
  }

  return _TokenPair(accessToken: accessToken, refreshToken: refreshToken);
}

bool isAccessTokenExpiredResponse(String responseBody) {
  return responseBody.trim().toLowerCase() == 'token expired';
}

bool isSessionFailureResponse(String responseBody) {
  final normalized = responseBody.trim().toLowerCase();
  return normalized == 'no token' ||
      normalized == 'invalid token' ||
      normalized == 'user not found' ||
      normalized == 'session not found' ||
      normalized == 'session revoked' ||
      normalized == 'session expired';
}

const _accessTokenKey = 'auth_access_token';
const _refreshTokenKey = 'auth_refresh_token';
