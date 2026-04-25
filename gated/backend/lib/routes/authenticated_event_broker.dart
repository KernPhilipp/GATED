import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/request_auth.dart';

typedef EventRequestAuthenticator = Future<void> Function(Request request);

class AuthenticatedEventBroker {
  AuthenticatedEventBroker({required this.path});

  final String path;
  final Set<WebSocketChannel> _clients = <WebSocketChannel>{};

  Handler handler({required EventRequestAuthenticator authenticate}) {
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
      if (request.url.path != path) {
        return Response.notFound('Not found');
      }

      final accessToken = request.url.queryParameters['accessToken'];
      if (accessToken == null || accessToken.trim().isEmpty) {
        return Response.forbidden('No token');
      }

      try {
        await authenticate(
          request.change(
            headers: {
              ...request.headers,
              'Authorization': 'Bearer ${accessToken.trim()}',
            },
          ),
        );
      } on RequestAuthenticationException catch (error) {
        return error.response;
      }

      return webSocket(request);
    };
  }

  void publish(Map<String, Object?> payload) {
    final timestampedPayload = {
      ...payload,
      'at': DateTime.now().toUtc().toIso8601String(),
    };
    final encodedPayload = jsonEncode(timestampedPayload);

    for (final client in List<WebSocketChannel>.from(_clients)) {
      try {
        client.sink.add(encodedPayload);
      } catch (_) {
        _clients.remove(client);
        client.sink.close();
      }
    }
  }
}
