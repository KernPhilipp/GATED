import 'dart:async';
import 'dart:io';

import '../db/database.dart';

String normalizeEmail(String email) => email.trim().toLowerCase();

class EmailAccessControlService {
  EmailAccessControlService({
    required DatabaseService db,
    required String allowedEmailsFilePath,
    String primaryAdminEmail = defaultPrimaryAdminEmail,
  }) : _db = db,
       _allowedEmailsFilePath = allowedEmailsFilePath,
       _primaryAdminEmail = normalizeEmail(primaryAdminEmail);

  static const defaultPrimaryAdminEmail = 'philipp.kern.student@htl-hallein.at';

  final DatabaseService _db;
  final String _allowedEmailsFilePath;
  final String _primaryAdminEmail;

  Future<void> _syncTail = Future.value();
  EmailAccessSnapshot _latestSnapshot = const EmailAccessSnapshot(
    allowedEmails: {},
    primaryAdminEmail: defaultPrimaryAdminEmail,
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

  Future<EmailAccessSnapshot> snapshot() async {
    await sync();
    return _latestSnapshot;
  }

  Future<void> addAllowedEmail(String email) async {
    final normalizedEmail = _validateWritableEmail(email);
    await sync();
    if (_latestSnapshot.allowedEmails.contains(normalizedEmail)) {
      throw const EmailAccessControlWriteException(
        EmailAccessControlWriteError.emailAlreadyAllowed,
      );
    }

    await _writeAllowedEmails({
      ..._latestSnapshot.allowedEmails,
      normalizedEmail,
    });
    await sync();
  }

  Future<void> updateAllowedEmail({
    required String currentEmail,
    required String newEmail,
  }) async {
    final currentNormalizedEmail = _validateWritableEmail(currentEmail);
    final newNormalizedEmail = _validateWritableEmail(newEmail);
    await sync();

    if (!_latestSnapshot.allowedEmails.contains(currentNormalizedEmail)) {
      throw const EmailAccessControlWriteException(
        EmailAccessControlWriteError.emailNotAllowed,
      );
    }

    if (currentNormalizedEmail != newNormalizedEmail &&
        _latestSnapshot.allowedEmails.contains(newNormalizedEmail)) {
      throw const EmailAccessControlWriteException(
        EmailAccessControlWriteError.emailAlreadyAllowed,
      );
    }

    final existingTargetUser = await _db.getUserByEmail(newNormalizedEmail);
    final currentUser = await _db.getUserByEmail(currentNormalizedEmail);
    if (existingTargetUser != null &&
        (currentUser == null || existingTargetUser.id != currentUser.id)) {
      throw const EmailAccessControlWriteException(
        EmailAccessControlWriteError.emailAlreadyRegistered,
      );
    }

    final updatedEmails = {..._latestSnapshot.allowedEmails}
      ..remove(currentNormalizedEmail)
      ..add(newNormalizedEmail);
    await _writeAllowedEmails(updatedEmails);

    if (currentUser != null && currentNormalizedEmail != newNormalizedEmail) {
      await _db.updateUserEmail(
        userId: currentUser.id,
        email: newNormalizedEmail,
      );
    }

    await sync();
  }

  Future<void> removeAllowedEmail(String email) async {
    final normalizedEmail = _validateWritableEmail(email);
    await sync();
    if (!_latestSnapshot.allowedEmails.contains(normalizedEmail)) {
      throw const EmailAccessControlWriteException(
        EmailAccessControlWriteError.emailNotAllowed,
      );
    }

    final updatedEmails = {..._latestSnapshot.allowedEmails}
      ..remove(normalizedEmail);
    await _writeAllowedEmails(updatedEmails);

    final user = await _db.getUserByEmail(normalizedEmail);
    if (user != null) {
      await _db.deleteUserById(user.id);
    }

    await sync();
  }

  Future<void> _performSync() async {
    final allowedEmails = await _readNormalizedEmails(_allowedEmailsFilePath);
    final snapshot = EmailAccessSnapshot(
      allowedEmails: allowedEmails,
      primaryAdminEmail: _primaryAdminEmail,
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

  String _validateWritableEmail(String email) {
    final normalizedEmail = normalizeEmail(email);
    if (normalizedEmail.isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizedEmail)) {
      throw const EmailAccessControlWriteException(
        EmailAccessControlWriteError.invalidEmail,
      );
    }

    if (normalizedEmail == _primaryAdminEmail) {
      throw const EmailAccessControlWriteException(
        EmailAccessControlWriteError.primaryAdminCannotBeModified,
      );
    }

    return normalizedEmail;
  }

  Future<void> _writeAllowedEmails(Set<String> emails) async {
    final file = File(_allowedEmailsFilePath);
    final parent = file.parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }

    final sortedEmails = emails.map(normalizeEmail).toSet().toList()
      ..sort((a, b) => a.compareTo(b));
    final content = sortedEmails.isEmpty ? '' : '${sortedEmails.join('\n')}\n';
    await file.writeAsString(content);
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

enum EmailAccessControlWriteError {
  invalidEmail,
  emailAlreadyAllowed,
  emailAlreadyRegistered,
  emailNotAllowed,
  primaryAdminCannotBeModified,
}

class EmailAccessControlWriteException implements Exception {
  const EmailAccessControlWriteException(this.error);

  final EmailAccessControlWriteError error;
}

class EmailAccessSnapshot {
  const EmailAccessSnapshot({
    required this.allowedEmails,
    required this.primaryAdminEmail,
  });

  final Set<String> allowedEmails;
  final String primaryAdminEmail;

  DbUserRole? roleForEmail(String email) {
    final normalizedEmail = normalizeEmail(email);
    if (normalizedEmail == primaryAdminEmail) {
      return DbUserRole.admin;
    }

    if (allowedEmails.contains(normalizedEmail)) {
      return DbUserRole.user;
    }

    return null;
  }
}
