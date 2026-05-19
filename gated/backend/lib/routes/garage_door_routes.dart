import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/email_access_control.dart';
import '../auth/request_auth.dart';
import '../db/database.dart';
import '../garage_door/garage_door_service.dart';
import 'request_helpers.dart';

Router buildGarageDoorRouter(
  GarageDoorService garageDoorService,
  DatabaseService authDb,
  EmailAccessControlService accessControlService,
) => Router()
  ..get('/garage-door/config', (Request request) async {
    try {
      await authenticateAdminRequest(request, authDb, accessControlService);
      return Response.ok(
        jsonEncode(garageDoorService.getConfig().toPublicJson()),
        headers: jsonHeaders,
      );
    } on RequestAuthenticationException catch (error) {
      return error.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..put('/garage-door/config', (Request request) async {
    final data = await readJsonObject(request);
    if (data == null) {
      return Response.badRequest(body: 'Invalid JSON body');
    }

    final baseUrl = readRequiredString(data, 'shellyBaseUrl');
    if (baseUrl == null) {
      return Response.badRequest(body: 'Missing shellyBaseUrl');
    }

    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !uri.isAbsolute ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return Response.badRequest(body: 'Invalid shellyBaseUrl');
    }

    try {
      await authenticateAdminRequest(request, authDb, accessControlService);
      final config = garageDoorService.getConfig().copyWith(
        shellyBaseUrl: baseUrl,
      );
      await authDb.saveGarageDoorConfig(config.toDbConfig());
      await garageDoorService.updateConfig(config);
      return Response.ok(
        jsonEncode(config.toPublicJson()),
        headers: jsonHeaders,
      );
    } on RequestAuthenticationException catch (error) {
      return error.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..get('/garage-door/status', (Request request) async {
    try {
      await authenticateRequest(request, authDb, accessControlService);
      final snapshot = await garageDoorService.getStatus();
      return Response.ok(jsonEncode(snapshot.toJson()), headers: jsonHeaders);
    } on RequestAuthenticationException catch (error) {
      return error.response;
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  })
  ..post('/garage-door/trigger', (Request request) async {
    try {
      await authenticateRequest(request, authDb, accessControlService);
      final snapshot = await garageDoorService.trigger();
      return Response.ok(jsonEncode(snapshot.toJson()), headers: jsonHeaders);
    } on RequestAuthenticationException catch (error) {
      return error.response;
    } on GarageDoorConflictException catch (error) {
      return Response(409, body: error.message);
    } on GarageDoorShellyException catch (error) {
      return Response(502, body: error.message);
    } catch (_) {
      return Response.internalServerError(body: 'Unexpected error');
    }
  });
