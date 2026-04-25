import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

const _jsonHeaders = {'Content-Type': 'application/json'};

Router buildAppInfoRouter({String versionFilePath = '../VERSION'}) => Router()
  ..get('/app/version', (_) async {
    final version = await _readInstalledVersion(versionFilePath);
    return Response.ok(jsonEncode({'version': version}), headers: _jsonHeaders);
  });

Future<String> _readInstalledVersion(String versionFilePath) async {
  final envVersion = Platform.environment['GATED_VERSION']?.trim();
  if (envVersion != null && envVersion.isNotEmpty) {
    return envVersion;
  }

  final versionFile = File(versionFilePath);
  if (await versionFile.exists()) {
    final fileVersion = (await versionFile.readAsString()).trim();
    if (fileVersion.isNotEmpty) {
      return fileVersion;
    }
  }

  return 'dev';
}
