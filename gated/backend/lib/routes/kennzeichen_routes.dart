import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

import '../auth/email_access_control.dart';
import '../auth/request_auth.dart';
import '../db/database.dart';
import '../db/license_plate_database.dart';
import 'authenticated_event_broker.dart';
import 'request_helpers.dart';

Router buildKennzeichenRouter(
  LicensePlateDatabaseService db,
  DatabaseService authDb,
  KennzeichenEventsBroker eventsBroker,
  EmailAccessControlService accessControlService,
) => Router()
  ..get('/kennzeichen', (Request request) async {
    try {
      await authenticateRequest(request, authDb, accessControlService);
      final entries = await db.getAllTeacherLicensePlates();
      return Response.ok(
        jsonEncode({'items': entries.map((entry) => entry.toJson()).toList()}),
        headers: jsonHeaders,
      );
    } on RequestAuthenticationException catch (e) {
      return e.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..post('/kennzeichen', (Request request) async {
    final data = await readJsonObject(request);
    if (data == null) {
      return Response.badRequest(body: 'Invalid JSON body');
    }

    final teacherName = readRequiredString(data, 'teacherName');
    final licensePlate = readRequiredString(data, 'licensePlate');
    if (teacherName == null || licensePlate == null) {
      return Response.badRequest(
        body: 'Missing teacherName and/or licensePlate',
      );
    }

    try {
      await authenticateRequest(request, authDb, accessControlService);
      final created = await db.createTeacherLicensePlate(
        teacherName: teacherName,
        licensePlate: licensePlate.toUpperCase(),
      );
      eventsBroker.publish(type: 'created', id: created.id);
      return Response(
        201,
        body: jsonEncode(created.toJson()),
        headers: jsonHeaders,
      );
    } on SqliteException catch (e) {
      if (_isUniqueConstraint(e)) {
        return Response(409, body: 'License plate already exists');
      }
      return Response.internalServerError(body: 'Database error');
    } on RequestAuthenticationException catch (e) {
      return e.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..put('/kennzeichen/<id>', (Request request, String id) async {
    final parsedId = int.tryParse(id);
    if (parsedId == null) {
      return Response.badRequest(body: 'Invalid id');
    }

    final data = await readJsonObject(request);
    if (data == null) {
      return Response.badRequest(body: 'Invalid JSON body');
    }

    final teacherName = readRequiredString(data, 'teacherName');
    final licensePlate = readRequiredString(data, 'licensePlate');
    if (teacherName == null || licensePlate == null) {
      return Response.badRequest(
        body: 'Missing teacherName and/or licensePlate',
      );
    }

    try {
      await authenticateRequest(request, authDb, accessControlService);
      final updated = await db.updateTeacherLicensePlate(
        id: parsedId,
        teacherName: teacherName,
        licensePlate: licensePlate.toUpperCase(),
      );
      if (updated == null) {
        return Response.notFound('Not found');
      }
      eventsBroker.publish(type: 'updated', id: updated.id);
      return Response.ok(jsonEncode(updated.toJson()), headers: jsonHeaders);
    } on SqliteException catch (e) {
      if (_isUniqueConstraint(e)) {
        return Response(409, body: 'License plate already exists');
      }
      return Response.internalServerError(body: 'Database error');
    } on RequestAuthenticationException catch (e) {
      return e.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..delete('/kennzeichen/<id>', (Request request, String id) async {
    final parsedId = int.tryParse(id);
    if (parsedId == null) {
      return Response.badRequest(body: 'Invalid id');
    }

    try {
      await authenticateRequest(request, authDb, accessControlService);
      final deleted = await db.deleteTeacherLicensePlate(parsedId);
      if (!deleted) {
        return Response.notFound('Not found');
      }
      eventsBroker.publish(type: 'deleted', id: parsedId);
      return Response(204);
    } on RequestAuthenticationException catch (e) {
      return e.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  });

bool _isUniqueConstraint(SqliteException error) {
  return error.extendedResultCode == 2067;
}

class KennzeichenEventsBroker {
  final AuthenticatedEventBroker _broker = AuthenticatedEventBroker(
    path: 'kennzeichen/events',
  );

  Handler handler(
    DatabaseService authDb,
    EmailAccessControlService accessControlService,
  ) {
    return _broker.handler(
      authenticate: (request) =>
          authenticateRequest(request, authDb, accessControlService),
    );
  }

  void publish({required String type, required int id}) {
    _broker.publish({'type': type, 'id': id});
  }
}
