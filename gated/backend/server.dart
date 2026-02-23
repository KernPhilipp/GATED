import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'lib/auth/jwt_service.dart';
import 'lib/db/database.dart';
import 'lib/db/license_plate_database.dart';
import 'lib/middleware/cors.dart';
import 'lib/routes/auth_routes.dart';
import 'lib/routes/kennzeichen_routes.dart';

void main() async {
  loadJwtEnv();
  // For testing, you can use an in-memory database:
  // final db = DatabaseService.openInMemory();
  final authDb = DatabaseService.open();
  final kennzeichenDb = LicensePlateDatabaseService.open();
  final apiHandler = Cascade()
      .add(buildAuthRouter(authDb).call)
      .add(buildKennzeichenRouter(kennzeichenDb).call)
      .handler;

  final handler = Pipeline().addMiddleware(cors()).addHandler(apiHandler);

  final server = await serve(handler, '0.0.0.0', 8080);

  print('Server running on port ${server.port}');
}
