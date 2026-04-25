import 'dart:async';
import 'dart:convert';

import '../config/app_config.dart';
import 'auth_service.dart';

class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.role,
    required this.isRegistered,
    required this.createdAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    final createdAtValue = json['createdAt'];
    final createdAt = createdAtValue is String && createdAtValue.isNotEmpty
        ? DateTime.tryParse(createdAtValue.replaceFirst(' ', 'T'))
        : null;

    return AdminUser(
      id: json['id'] as int?,
      email: json['email'] as String,
      role: AuthUserRoleX.fromWireName(json['role'] as String?),
      isRegistered: json['isRegistered'] as bool,
      createdAt: createdAt,
    );
  }

  final int? id;
  final String email;
  final AuthUserRole role;
  final bool isRegistered;
  final DateTime? createdAt;

  bool get isAdmin => role == AuthUserRole.admin;
  bool get canResetPassword => !isAdmin && isRegistered && id != null;
  bool get canDelete => !isAdmin;
  bool get canEdit => !isAdmin;

  String get roleLabel {
    return isAdmin ? 'Admin' : 'User';
  }
}

class AdminPasswordResetResult {
  const AdminPasswordResetResult({
    required this.email,
    required this.temporaryPassword,
  });

  factory AdminPasswordResetResult.fromJson(Map<String, dynamic> json) {
    return AdminPasswordResetResult(
      email: json['email'] as String,
      temporaryPassword: json['temporaryPassword'] as String,
    );
  }

  final String email;
  final String temporaryPassword;
}

class AdminService {
  AdminService({
    String baseUrl = AppConfig.apiBaseUrl,
    AuthService? authService,
  }) : _authService = authService ?? AuthService(baseUrl: baseUrl);

  final AuthService _authService;

  Future<List<AdminUser>> fetchUsers() async {
    final response = await _authService
        .sendAuthorizedRequest(method: 'GET', path: '/admin/users')
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw AdminException(_messageForStatus(response.statusCode));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const AdminException('Ungueltige Server-Antwort.');
    }

    return decoded.map<AdminUser>((entry) {
      if (entry is! Map) {
        throw const AdminException('Ungueltige Server-Antwort.');
      }

      return AdminUser.fromJson(
        entry.map((key, value) => MapEntry('$key', value)),
      );
    }).toList();
  }

  Future<void> deleteUser(int id) async {
    final response = await _authService
        .sendAuthorizedRequest(method: 'DELETE', path: '/admin/users/$id')
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 204) {
      return;
    }

    throw AdminException(_messageForStatus(response.statusCode));
  }

  Future<void> addAllowedEmail(String email) async {
    final response = await _authService
        .sendAuthorizedRequest(
          method: 'POST',
          path: '/admin/allowed-emails',
          body: jsonEncode({'email': email}),
          includeJsonContentType: true,
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 201) {
      return;
    }

    throw AdminException(_messageForStatus(response.statusCode));
  }

  Future<void> updateAllowedEmail({
    required String currentEmail,
    required String newEmail,
  }) async {
    final encodedEmail = Uri.encodeComponent(currentEmail);
    final response = await _authService
        .sendAuthorizedRequest(
          method: 'PUT',
          path: '/admin/allowed-emails/$encodedEmail',
          body: jsonEncode({'email': newEmail}),
          includeJsonContentType: true,
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return;
    }

    throw AdminException(_messageForStatus(response.statusCode));
  }

  Future<void> deleteAllowedEmail(String email) async {
    final encodedEmail = Uri.encodeComponent(email);
    final response = await _authService
        .sendAuthorizedRequest(
          method: 'DELETE',
          path: '/admin/allowed-emails/$encodedEmail',
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 204) {
      return;
    }

    throw AdminException(_messageForStatus(response.statusCode));
  }

  Future<AdminPasswordResetResult> resetPassword(int id) async {
    final response = await _authService
        .sendAuthorizedRequest(
          method: 'POST',
          path: '/admin/users/$id/reset-password',
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw AdminException(_messageForStatus(response.statusCode));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const AdminException('Ungueltige Server-Antwort.');
    }

    return AdminPasswordResetResult.fromJson(
      decoded.map((key, value) => MapEntry('$key', value)),
    );
  }

  String _messageForStatus(int statusCode) {
    switch (statusCode) {
      case 401:
      case 403:
        return 'Keine Berechtigung fuer diesen Bereich.';
      case 404:
        return 'Benutzer oder E-Mail wurde nicht gefunden.';
      case 409:
        return 'Diese E-Mail kann nicht bearbeitet werden.';
      case 500:
        return 'Serverfehler. Bitte spaeter versuchen.';
      default:
        return 'Aktion konnte nicht ausgefuehrt werden.';
    }
  }
}

class AdminException implements Exception {
  const AdminException(this.message);

  final String message;
}
