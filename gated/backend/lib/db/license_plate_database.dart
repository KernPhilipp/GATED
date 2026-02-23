import 'package:sqlite3/sqlite3.dart';

class DbTeacherLicensePlate {
  final int id;
  final String teacherName;
  final String licensePlate;
  final String createdAt;
  final String updatedAt;

  const DbTeacherLicensePlate({
    required this.id,
    required this.teacherName,
    required this.licensePlate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DbTeacherLicensePlate.fromRow(Row row) {
    return DbTeacherLicensePlate(
      id: row['id'] as int,
      teacherName: row['teacher_name'] as String,
      licensePlate: row['license_plate'] as String,
      createdAt: row['created_at'] as String,
      updatedAt: row['updated_at'] as String,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'teacherName': teacherName,
      'licensePlate': licensePlate,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

class LicensePlateDatabaseService {
  final Database db;

  LicensePlateDatabaseService._(this.db);

  static LicensePlateDatabaseService? _instance;

  static LicensePlateDatabaseService open({String path = 'kennzeichen.db'}) {
    if (_instance != null) {
      return _instance!;
    }

    final db = sqlite3.open(path);
    db.execute('PRAGMA foreign_keys = ON;');
    _initSchema(db);

    _instance = LicensePlateDatabaseService._(db);
    return _instance!;
  }

  static LicensePlateDatabaseService openInMemory() {
    final db = sqlite3.openInMemory();
    db.execute('PRAGMA foreign_keys = ON;');
    _initSchema(db);
    return LicensePlateDatabaseService._(db);
  }

  static void _initSchema(Database db) {
    db.execute('''
CREATE TABLE IF NOT EXISTS teacher_license_plates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  teacher_name TEXT NOT NULL,
  license_plate TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);
''');

    db.execute('''
CREATE INDEX IF NOT EXISTS idx_teacher_license_plates_teacher_name
ON teacher_license_plates(teacher_name);
''');

    db.execute('''
CREATE INDEX IF NOT EXISTS idx_teacher_license_plates_license_plate
ON teacher_license_plates(license_plate);
''');
  }

  void close() {
    db.close();
    if (identical(_instance, this)) {
      _instance = null;
    }
  }

  Future<List<DbTeacherLicensePlate>> getAllTeacherLicensePlates() async {
    final stmt = db.prepare('''
SELECT id, teacher_name, license_plate, created_at, updated_at
FROM teacher_license_plates
ORDER BY teacher_name COLLATE NOCASE ASC;
''');
    try {
      return stmt.select().map(DbTeacherLicensePlate.fromRow).toList();
    } finally {
      stmt.close();
    }
  }

  Future<DbTeacherLicensePlate> createTeacherLicensePlate({
    required String teacherName,
    required String licensePlate,
  }) async {
    final stmt = db.prepare('''
INSERT INTO teacher_license_plates (teacher_name, license_plate)
VALUES (?, ?);
''');
    try {
      stmt.execute([teacherName, licensePlate]);
    } finally {
      stmt.close();
    }

    final insertedId = db.lastInsertRowId;
    final inserted = await getTeacherLicensePlateById(insertedId);
    if (inserted == null) {
      throw StateError('Inserted teacher license plate row not found.');
    }
    return inserted;
  }

  Future<DbTeacherLicensePlate?> getTeacherLicensePlateById(int id) async {
    final stmt = db.prepare('''
SELECT id, teacher_name, license_plate, created_at, updated_at
FROM teacher_license_plates
WHERE id = ?;
''');
    try {
      final result = stmt.select([id]);
      if (result.isEmpty) {
        return null;
      }
      return DbTeacherLicensePlate.fromRow(result.first);
    } finally {
      stmt.close();
    }
  }

  Future<DbTeacherLicensePlate?> updateTeacherLicensePlate({
    required int id,
    required String teacherName,
    required String licensePlate,
  }) async {
    final stmt = db.prepare('''
UPDATE teacher_license_plates
SET teacher_name = ?,
    license_plate = ?,
    updated_at = datetime('now', 'localtime')
WHERE id = ?;
''');
    try {
      stmt.execute([teacherName, licensePlate, id]);
    } finally {
      stmt.close();
    }

    return getTeacherLicensePlateById(id);
  }

  Future<bool> deleteTeacherLicensePlate(int id) async {
    final stmt = db.prepare('DELETE FROM teacher_license_plates WHERE id = ?;');
    try {
      stmt.execute([id]);
      return db.updatedRows > 0;
    } finally {
      stmt.close();
    }
  }
}
