import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'lib/middleware/cors.dart';
import 'lib/routes/auth_routes.dart';
import 'lib/auth/jwt_service.dart';
import 'lib/db/database.dart';

void main() async {
  loadJwtEnv();
  final db = DatabaseService.open();
  // For testing, you can use an in-memory database:
  // final db = DatabaseService.openInMemory();
  final handler = Pipeline()
      .addMiddleware(cors())
      .addHandler(buildAuthRouter(db).call);

  final server = await serve(handler, '0.0.0.0', 8080);

  print('Server running on port ${server.port}');
}
