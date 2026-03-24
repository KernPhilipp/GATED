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
}
