import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/email_access_control.dart';
import '../auth/request_auth.dart';
import '../db/database.dart';
import '../db/license_plate_database.dart';

const _jsonHeaders = {'Content-Type': 'application/json'};

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
        headers: _jsonHeaders,
      );
    } on RequestAuthenticationException catch (e) {
      return e.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..post('/kennzeichen', (Request request) async {
    final data = await _readJsonObject(request);
    if (data == null) {
      return Response.badRequest(body: 'Invalid JSON body');
    }

    final teacherName = _readRequiredString(data, 'teacherName');
    final licensePlate = _readRequiredString(data, 'licensePlate');
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
        headers: _jsonHeaders,
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

    final data = await _readJsonObject(request);
    if (data == null) {
      return Response.badRequest(body: 'Invalid JSON body');
    }

    final teacherName = _readRequiredString(data, 'teacherName');
    final licensePlate = _readRequiredString(data, 'licensePlate');
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
      return Response.ok(jsonEncode(updated.toJson()), headers: _jsonHeaders);
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

Future<Map<String, dynamic>?> _readJsonObject(Request request) async {
  final raw = await request.readAsString();
  if (raw.trim().isEmpty) {
    return null;
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  } catch (_) {
    return null;
  }

  return null;
}

String? _readRequiredString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

bool _isUniqueConstraint(SqliteException error) {
  return error.extendedResultCode == 2067;
}

class KennzeichenEventsBroker {
  final Set<WebSocketChannel> _clients = <WebSocketChannel>{};

  Handler handler(
    DatabaseService authDb,
    EmailAccessControlService accessControlService,
  ) {
    final webSocket = webSocketHandler((channel, _) {
      _clients.add(channel);
      channel.stream.listen(
        (_) {},
        onDone: () => _clients.remove(channel),
        onError: (_, __) => _clients.remove(channel),
        cancelOnError: true,
      );
    });

    return (Request request) async {
      if (request.url.path != 'kennzeichen/events') {
        return Response.notFound('Not found');
      }

      final accessToken = request.url.queryParameters['accessToken'];
      if (accessToken == null || accessToken.trim().isEmpty) {
        return Response.forbidden('No token');
      }

      try {
        await authenticateRequest(
          request.change(
            headers: {
              ...request.headers,
              'Authorization': 'Bearer ${accessToken.trim()}',
            },
          ),
          authDb,
          accessControlService,
        );
      } on RequestAuthenticationException catch (error) {
        return error.response;
      }

      return webSocket(request);
    };
  }

  void publish({required String type, required int id}) {
    final payload = jsonEncode({
      'type': type,
      'id': id,
      'at': DateTime.now().toUtc().toIso8601String(),
    });

    for (final client in List<WebSocketChannel>.from(_clients)) {
      try {
        client.sink.add(payload);
      } catch (_) {
        _clients.remove(client);
        client.sink.close();
      }
    }
  }
}
