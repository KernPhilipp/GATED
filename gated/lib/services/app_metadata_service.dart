import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class AppMetadataService {
  const AppMetadataService({String baseUrl = AppConfig.apiBaseUrl})
    : _baseUrl = baseUrl;

  final String _baseUrl;

  Future<String> loadAppVersion() async {
    final response = await http
        .get(Uri.parse('$_baseUrl/app/version'))
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      throw const AppMetadataException('Version konnte nicht geladen werden.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const AppMetadataException('Ungueltige Server-Antwort.');
    }

    final version = decoded['version'];
    if (version is! String || version.trim().isEmpty) {
      throw const AppMetadataException('Ungueltige Server-Antwort.');
    }

    return version.trim();
  }
}

class AppMetadataException implements Exception {
  const AppMetadataException(this.message);

  final String message;
}
