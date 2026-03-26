import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'auth_service.dart';

class KennzeichenEntry {
  final int id;
  final String teacherName;
  final String licensePlate;
  final String? createdAt;
  final String? updatedAt;

  const KennzeichenEntry({
    required this.id,
    required this.teacherName,
    required this.licensePlate,
    this.createdAt,
    this.updatedAt,
  });

  factory KennzeichenEntry.fromJson(Map<String, dynamic> json) {
    return KennzeichenEntry(
      id: json['id'] as int,
      teacherName: json['teacherName'] as String,
      licensePlate: json['licensePlate'] as String,
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
    );
  }
}

class KennzeichenService {
  const KennzeichenService({
    this.baseUrl = AppConfig.apiBaseUrl,
    AuthService authService = const AuthService(),
  }) : _authService = authService;

  final String baseUrl;
  final AuthService _authService;

  Future<List<KennzeichenEntry>> fetchEntries() async {
    final response = await http.get(
      Uri.parse('$_normalizedBaseUrl/kennzeichen'),
      headers: await _authService.authorizedHeaders(),
    );

    if (response.statusCode == 403 && isTokenErrorResponse(response.body)) {
      await _authService.clearToken();
      throw const SessionExpiredException();
    }

    if (response.statusCode != 200) {
      throw KennzeichenException(_messageForStatus(response.statusCode));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const KennzeichenException('Ungültige Server-Antwort.');
    }

    final items = decoded['items'];
    if (items is! List) {
      throw const KennzeichenException('Ungültige Server-Antwort.');
    }

    return items
        .whereType<Map>()
        .map(
          (item) => KennzeichenEntry.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
  }

  Future<KennzeichenEntry> createEntry({
    required String teacherName,
    required String licensePlate,
  }) async {
    final response = await http.post(
      Uri.parse('$_normalizedBaseUrl/kennzeichen'),
      headers: await _authService.authorizedHeaders(
        includeJsonContentType: true,
      ),
      body: jsonEncode({
        'teacherName': teacherName,
        'licensePlate': licensePlate,
      }),
    );

    if (response.statusCode == 403 && isTokenErrorResponse(response.body)) {
      await _authService.clearToken();
      throw const SessionExpiredException();
    }

    if (response.statusCode != 201) {
      throw KennzeichenException(_messageForStatus(response.statusCode));
    }

    return _parseEntryResponse(response.body);
  }

  Future<KennzeichenEntry> updateEntry({
    required int id,
    required String teacherName,
    required String licensePlate,
  }) async {
    final response = await http.put(
      Uri.parse('$_normalizedBaseUrl/kennzeichen/$id'),
      headers: await _authService.authorizedHeaders(
        includeJsonContentType: true,
      ),
      body: jsonEncode({
        'teacherName': teacherName,
        'licensePlate': licensePlate,
      }),
    );

    if (response.statusCode == 403 && isTokenErrorResponse(response.body)) {
      await _authService.clearToken();
      throw const SessionExpiredException();
    }

    if (response.statusCode != 200) {
      throw KennzeichenException(_messageForStatus(response.statusCode));
    }

    return _parseEntryResponse(response.body);
  }

  Future<void> deleteEntry(int id) async {
    final response = await http.delete(
      Uri.parse('$_normalizedBaseUrl/kennzeichen/$id'),
      headers: await _authService.authorizedHeaders(),
    );

    if (response.statusCode == 403 && isTokenErrorResponse(response.body)) {
      await _authService.clearToken();
      throw const SessionExpiredException();
    }

    if (response.statusCode != 204) {
      throw KennzeichenException(_messageForStatus(response.statusCode));
    }
  }

  KennzeichenEntry _parseEntryResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const KennzeichenException('Ungültige Server-Antwort.');
    }

    return KennzeichenEntry.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  String _messageForStatus(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Bitte Lehrername und Kennzeichen angeben.';
      case 404:
        return 'Eintrag wurde nicht gefunden.';
      case 409:
        return 'Kennzeichen existiert bereits.';
      case 500:
        return 'Serverfehler. Bitte später versuchen.';
      default:
        return 'Server-Fehler. Bitte später versuchen.';
    }
  }

  String get _normalizedBaseUrl => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
}

class KennzeichenException implements Exception {
  const KennzeichenException(this.message);

  final String message;
}
