import 'dart:convert';
import 'dart:io';

import 'package:gated_backend/routes/app_info_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gated-app-info-test-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('app version reads the installed VERSION file', () async {
    final versionFile = File('${tempDir.path}/VERSION');
    versionFile.writeAsStringSync('v0.1.7\n');
    final handler = buildAppInfoRouter(versionFilePath: versionFile.path).call;

    final response = await handler(
      Request('GET', Uri.parse('http://localhost/app/version')),
    );

    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['version'], 'v0.1.7');
  });

  test('app version falls back to dev without release metadata', () async {
    final handler = buildAppInfoRouter(
      versionFilePath: '${tempDir.path}/missing-version',
    ).call;

    final response = await handler(
      Request('GET', Uri.parse('http://localhost/app/version')),
    );

    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['version'], 'dev');
  });
}
