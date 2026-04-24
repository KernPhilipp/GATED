import 'dart:async';
import 'dart:io';

import '../db/database.dart';

String normalizeEmail(String email) => email.trim().toLowerCase();

class EmailAccessControlService {
  EmailAccessControlService({
    required DatabaseService db,
    required String allowedEmailsFilePath,
    required String adminEmailsFilePath,
  }) : _db = db,
       _allowedEmailsFilePath = allowedEmailsFilePath,
       _adminEmailsFilePath = adminEmailsFilePath;

  final DatabaseService _db;
  final String _allowedEmailsFilePath;
  final String _adminEmailsFilePath;

  Future<void> _syncTail = Future.value();
  EmailAccessSnapshot _latestSnapshot = const EmailAccessSnapshot(
    allowedEmails: {},
    adminEmails: {},
  );

  Future<void> sync() {
    final syncFuture = _syncTail.catchError((_) {}).then((_) => _performSync());
    _syncTail = syncFuture;
    return syncFuture;
  }

  Future<DbUserRole?> roleForEmail(String email) async {
    await sync();
    return _latestSnapshot.roleForEmail(email);
  }

  Future<bool> isEmailAllowed(String email) async {
    return (await roleForEmail(email)) != null;
  }

  Future<void> _performSync() async {
    final allowedEmails = await _readNormalizedEmails(_allowedEmailsFilePath);
    final adminEmails = await _readNormalizedEmails(_adminEmailsFilePath);
    final snapshot = EmailAccessSnapshot(
      allowedEmails: allowedEmails,
      adminEmails: adminEmails,
    );

    final users = await _db.getAllUsers();
    for (final user in users) {
      final targetRole = snapshot.roleForEmail(user.email);
      if (targetRole == null) {
        await _db.deleteUserById(user.id);
        continue;
      }

      if (user.role != targetRole) {
        await _db.updateUserRole(userId: user.id, role: targetRole);
      }
    }

    _latestSnapshot = snapshot;
  }

  Future<Set<String>> _readNormalizedEmails(String path) async {
    final file = _resolveExistingFile(path);
    if (file == null) {
      return <String>{};
    }

    final lines = await file.readAsLines();
    return lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .map(normalizeEmail)
        .toSet();
  }

  File? _resolveExistingFile(String path) {
    final file = File(path);
    if (file.existsSync()) {
      return file;
    }

    if (!path.endsWith('.txt')) {
      return null;
    }

    final examplePath = '${path.substring(0, path.length - 4)}.example.txt';
    final exampleFile = File(examplePath);
    if (exampleFile.existsSync()) {
      return exampleFile;
    }

    return null;
  }
}

class EmailAccessSnapshot {
  const EmailAccessSnapshot({
    required this.allowedEmails,
    required this.adminEmails,
  });

  final Set<String> allowedEmails;
  final Set<String> adminEmails;

  DbUserRole? roleForEmail(String email) {
    final normalizedEmail = normalizeEmail(email);
    if (adminEmails.contains(normalizedEmail)) {
      return DbUserRole.admin;
    }

    if (allowedEmails.contains(normalizedEmail)) {
      return DbUserRole.user;
    }

    return null;
  }
}
