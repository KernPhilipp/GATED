import 'dart:convert';

import 'package:shelf/shelf.dart';

const jsonHeaders = {'Content-Type': 'application/json'};

Future<Map<String, dynamic>?> readJsonObject(Request request) async {
  final raw = await request.readAsString();
  if (raw.trim().isEmpty) {
    return null;
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value));
    }
  } catch (_) {
    return null;
  }

  return null;
}

String? readRequiredString(Map<String, dynamic>? data, String key) {
  if (data == null) {
    return null;
  }

  final value = data[key];
  if (value is! String) {
    return null;
  }

  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
