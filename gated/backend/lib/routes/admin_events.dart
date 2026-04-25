import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/email_access_control.dart';
import '../auth/request_auth.dart';
import '../db/database.dart';

class AdminEventsBroker {
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
      if (request.url.path != 'admin/events') {
        return Response.notFound('Not found');
      }

      final accessToken = request.url.queryParameters['accessToken'];
      if (accessToken == null || accessToken.trim().isEmpty) {
        return Response.forbidden('No token');
      }

      try {
        await authenticateAdminRequest(
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

  void publish({required String type, required String email}) {
    final payload = jsonEncode({
      'type': type,
      'email': normalizeEmail(email),
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
