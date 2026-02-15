import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  const AuthService({this.baseUrl = 'http://localhost:8080'});

  final String baseUrl;
  static final Future<SharedPreferencesWithCache> _prefs =
      SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(
          allowList: <String>{_tokenKey},
        ),
      );

  Future<String> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
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
      Uri.parse('$baseUrl/auth/register'),
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

  Future<void> _saveToken(String token) async {
    final prefs = await _prefs;
    await prefs.setString(_tokenKey, token);
  }

  Future<String?> readToken() async {
    final prefs = await _prefs;
    return prefs.getString(_tokenKey);
  }

  Future<void> clearToken() async {
    final prefs = await _prefs;
    await prefs.remove(_tokenKey);
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;
}

const _tokenKey = 'auth_token';
