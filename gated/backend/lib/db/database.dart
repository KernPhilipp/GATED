import 'package:sqlite3/sqlite3.dart';

class DbUser {
  final int id;
  final String email;
  final String passwordHash;
  final String salt;
  final String createdAt;

  const DbUser({
    required this.id,
    required this.email,
    required this.passwordHash,
    required this.salt,
    required this.createdAt,
  });

  factory DbUser.fromRow(Row row) {
    return DbUser(
      id: row['id'] as int,
      email: row['email'] as String,
      passwordHash: row['password_hash'] as String,
      salt: row['password_salt'] as String,
      createdAt: row['created_at'] as String,
    );
  }
}

class DbAuthSession {
  final String id;
  final int userId;
  final String refreshTokenHash;
  final String createdAt;
  final String expiresAt;
  final String? revokedAt;
  final String? lastUsedAt;

  const DbAuthSession({
    required this.id,
    required this.userId,
    required this.refreshTokenHash,
    required this.createdAt,
    required this.expiresAt,
    required this.revokedAt,
    required this.lastUsedAt,
  });

  factory DbAuthSession.fromRow(Row row) {
    return DbAuthSession(
      id: row['id'] as String,
      userId: row['user_id'] as int,
      refreshTokenHash: row['refresh_token_hash'] as String,
      createdAt: row['created_at'] as String,
      expiresAt: row['expires_at'] as String,
      revokedAt: row['revoked_at'] as String?,
      lastUsedAt: row['last_used_at'] as String?,
    );
  }
}

class DatabaseService {
  final Database db;

  DatabaseService._(this.db);

  static DatabaseService? _instance;

  static DatabaseService open({String path = 'gated.db'}) {
    if (_instance != null) {
      return _instance!;
    }

    final db = sqlite3.open(path);
    db.execute('PRAGMA foreign_keys = ON;');
    _initSchema(db);

    _instance = DatabaseService._(db);
    return _instance!;
  }

  static DatabaseService openInMemory() {
    final db = sqlite3.openInMemory();
    db.execute('PRAGMA foreign_keys = ON;');
    _initSchema(db);
    return DatabaseService._(db);
  }

  static void _initSchema(Database db) {
    db.execute('''
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  password_salt TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);
''');

    db.execute('CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);');

    db.execute('''
CREATE TABLE IF NOT EXISTS auth_sessions (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL,
  refresh_token_hash TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  revoked_at TEXT,
  last_used_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
''');

    db.execute('''
CREATE INDEX IF NOT EXISTS idx_auth_sessions_user_id
ON auth_sessions(user_id);
''');

    db.execute('''
CREATE INDEX IF NOT EXISTS idx_auth_sessions_expires_at
ON auth_sessions(expires_at);
''');
  }

  void close() {
    db.close();
    if (identical(_instance, this)) {
      _instance = null;
    }
  }

  Future<void> createUser({
    required String email,
    required String passwordHash,
    required String salt,
  }) async {
    final stmt = db.prepare('''
INSERT INTO users (email, password_hash, password_salt)
VALUES (?, ?, ?);
''');
    try {
      stmt.execute([email, passwordHash, salt]);
    } finally {
      stmt.close();
    }
  }

  Future<DbUser?> getUserByEmail(String email) async {
    final stmt = db.prepare('''
SELECT id, email, password_hash, password_salt, created_at
FROM users
WHERE email = ?
LIMIT 1;
''');
    try {
      final result = stmt.select([email]);
      if (result.isEmpty) {
        return null;
      }
      return DbUser.fromRow(result.first);
    } finally {
      stmt.close();
    }
  }

  Future<DbUser?> getUserById(int id) async {
    final stmt = db.prepare('''
SELECT id, email, password_hash, password_salt, created_at
FROM users
WHERE id = ?
LIMIT 1;
''');
    try {
      final result = stmt.select([id]);
      if (result.isEmpty) {
        return null;
      }
      return DbUser.fromRow(result.first);
    } finally {
      stmt.close();
    }
  }

  Future<void> updateUserPassword({
    required int userId,
    required String passwordHash,
    required String salt,
  }) async {
    final stmt = db.prepare('''
UPDATE users
SET password_hash = ?, password_salt = ?
WHERE id = ?;
''');
    try {
      stmt.execute([passwordHash, salt, userId]);
    } finally {
      stmt.close();
    }
  }

  Future<void> createAuthSession({
    required String sessionId,
    required int userId,
    required String refreshTokenHash,
    required String createdAt,
    required String expiresAt,
    String? lastUsedAt,
  }) async {
    final stmt = db.prepare('''
INSERT INTO auth_sessions (
  id,
  user_id,
  refresh_token_hash,
  created_at,
  expires_at,
  last_used_at
)
VALUES (?, ?, ?, ?, ?, ?);
''');
    try {
      stmt.execute([
        sessionId,
        userId,
        refreshTokenHash,
        createdAt,
        expiresAt,
        lastUsedAt,
      ]);
    } finally {
      stmt.close();
    }
  }

  Future<DbAuthSession?> getAuthSessionById(String sessionId) async {
    final stmt = db.prepare('''
SELECT id, user_id, refresh_token_hash, created_at, expires_at, revoked_at,
       last_used_at
FROM auth_sessions
WHERE id = ?
LIMIT 1;
''');
    try {
      final result = stmt.select([sessionId]);
      if (result.isEmpty) {
        return null;
      }
      return DbAuthSession.fromRow(result.first);
    } finally {
      stmt.close();
    }
  }

  Future<DbAuthSession?> getAuthSessionByRefreshTokenHash(
    String refreshTokenHash,
  ) async {
    final stmt = db.prepare('''
SELECT id, user_id, refresh_token_hash, created_at, expires_at, revoked_at,
       last_used_at
FROM auth_sessions
WHERE refresh_token_hash = ?
LIMIT 1;
''');
    try {
      final result = stmt.select([refreshTokenHash]);
      if (result.isEmpty) {
        return null;
      }
      return DbAuthSession.fromRow(result.first);
    } finally {
      stmt.close();
    }
  }

  Future<void> rotateAuthSessionRefreshToken({
    required String sessionId,
    required String refreshTokenHash,
    required String expiresAt,
    required String lastUsedAt,
  }) async {
    final stmt = db.prepare('''
UPDATE auth_sessions
SET refresh_token_hash = ?,
    expires_at = ?,
    last_used_at = ?
WHERE id = ?;
''');
    try {
      stmt.execute([refreshTokenHash, expiresAt, lastUsedAt, sessionId]);
    } finally {
      stmt.close();
    }
  }

  Future<void> revokeAuthSession({
    required String sessionId,
    required String revokedAt,
  }) async {
    final stmt = db.prepare('''
UPDATE auth_sessions
SET revoked_at = COALESCE(revoked_at, ?)
WHERE id = ?;
''');
    try {
      stmt.execute([revokedAt, sessionId]);
    } finally {
      stmt.close();
    }
  }

  Future<void> revokeAllAuthSessionsForUser({
    required int userId,
    required String revokedAt,
  }) async {
    final stmt = db.prepare('''
UPDATE auth_sessions
SET revoked_at = COALESCE(revoked_at, ?)
WHERE user_id = ?;
''');
    try {
      stmt.execute([revokedAt, userId]);
    } finally {
      stmt.close();
    }
  }
}
