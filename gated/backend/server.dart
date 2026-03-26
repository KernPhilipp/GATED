import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'lib/auth/jwt_service.dart';
import 'lib/db/database.dart';
import 'lib/db/license_plate_database.dart';
import 'lib/middleware/cors.dart';
import 'lib/routes/auth_routes.dart';
import 'lib/routes/kennzeichen_routes.dart';

void main() async {
  loadJwtEnv();
  final port = _readPortFromEnv(defaultValue: 8091);
  final authDbPath = _readStringFromEnv(
    'AUTH_DB_PATH',
    defaultValue: 'gated.db',
  );
  final kennzeichenDbPath = _readStringFromEnv(
    'KENNZEICHEN_DB_PATH',
    defaultValue: 'kennzeichen.db',
  );

  // For testing, you can use an in-memory database:
  // final db = DatabaseService.openInMemory();
  final authDb = DatabaseService.open(path: authDbPath);
  final kennzeichenDb = LicensePlateDatabaseService.open(
    path: kennzeichenDbPath,
  );
  final healthRouter = Router()..get('/health', (_) => Response.ok('ok'));
  final apiHandler = Cascade()
      .add(healthRouter.call)
      .add(buildAuthRouter(authDb).call)
      .add(buildKennzeichenRouter(kennzeichenDb, authDb).call)
      .handler;

  final handler = Pipeline().addMiddleware(cors()).addHandler(apiHandler);

  final server = await serve(handler, '0.0.0.0', port);

  stdout.writeln(
    'Server running on port ${server.port} (auth db: $authDbPath, kennzeichen db: $kennzeichenDbPath)',
  );
}

String _readStringFromEnv(String key, {required String defaultValue}) {
  final rawValue = Platform.environment[key];
  if (rawValue == null) {
    return defaultValue;
  }

  final trimmed = rawValue.trim();
  return trimmed.isEmpty ? defaultValue : trimmed;
}

int _readPortFromEnv({required int defaultValue}) {
  final rawValue = Platform.environment['PORT'];
  if (rawValue == null) {
    return defaultValue;
  }

  final parsed = int.tryParse(rawValue.trim());
  if (parsed == null || parsed <= 0 || parsed > 65535) {
    stderr.writeln('Invalid PORT="$rawValue". Falling back to $defaultValue.');
    return defaultValue;
  }

  return parsed;
}
