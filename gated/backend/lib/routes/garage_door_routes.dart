import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/request_auth.dart';
import '../db/database.dart';
import '../garage_door/garage_door_service.dart';

const _jsonHeaders = {'Content-Type': 'application/json'};

Router buildGarageDoorRouter(
  GarageDoorService garageDoorService,
  DatabaseService authDb,
) => Router()
  ..get('/garage-door/status', (Request request) async {
    try {
      await authenticateRequest(request, authDb);
      final snapshot = await garageDoorService.getStatus();
      return Response.ok(jsonEncode(snapshot.toJson()), headers: _jsonHeaders);
    } on RequestAuthenticationException catch (error) {
      return error.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..post('/garage-door/trigger', (Request request) async {
    try {
      await authenticateRequest(request, authDb);
      final snapshot = await garageDoorService.trigger();
      return Response.ok(jsonEncode(snapshot.toJson()), headers: _jsonHeaders);
    } on RequestAuthenticationException catch (error) {
      return error.response;
    } on GarageDoorConflictException catch (error) {
      return Response(409, body: error.message);
    } on GarageDoorShellyException catch (error) {
      return Response(502, body: error.message);
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..post('/garage-door/state', (Request request) async {
    final data = await _readJsonObject(request);
    if (data == null) {
      return Response.badRequest(body: 'Invalid JSON body');
    }

    final stateName = _readRequiredString(data, 'state');
    if (stateName == null) {
      return Response.badRequest(body: 'Missing state');
    }

    final state = switch (stateName.trim().toLowerCase()) {
      'open' => GarageDoorState.open,
      'closed' => GarageDoorState.closed,
      'unknown' => GarageDoorState.unknown,
      _ => null,
    };

    if (state == null) {
      return Response.badRequest(body: 'Unsupported state');
    }

    try {
      await authenticateRequest(request, authDb);
      final snapshot = garageDoorService.setManualState(state);
      return Response.ok(jsonEncode(snapshot.toJson()), headers: _jsonHeaders);
    } on RequestAuthenticationException catch (error) {
      return error.response;
    } on GarageDoorConflictException catch (error) {
      return Response(409, body: error.message);
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
      return decoded.map((key, value) => MapEntry('$key', value));
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
  return trimmed.isEmpty ? null : trimmed;
}
