import 'package:shelf/shelf.dart';

import '../auth/email_access_control.dart';
import '../auth/request_auth.dart';
import '../db/database.dart';
import 'authenticated_event_broker.dart';

class AdminEventsBroker {
  final AuthenticatedEventBroker _broker = AuthenticatedEventBroker(
    path: 'admin/events',
  );

  Handler handler(
    DatabaseService authDb,
    EmailAccessControlService accessControlService,
  ) {
    return _broker.handler(
      authenticate: (request) =>
          authenticateAdminRequest(request, authDb, accessControlService),
    );
  }

  void publish({required String type, required String email}) {
    _broker.publish({'type': type, 'email': normalizeEmail(email)});
  }
}
