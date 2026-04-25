import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';
import 'auth_service.dart';

class RealtimeEventSubscription {
  RealtimeEventSubscription({
    required AuthService authService,
    required String path,
    required bool Function() canConnect,
    required void Function() onEvent,
  }) : _authService = authService,
       _path = path,
       _canConnect = canConnect,
       _onEvent = onEvent;

  final AuthService _authService;
  final String _path;
  final bool Function() _canConnect;
  final void Function() _onEvent;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _isConnecting = false;
  bool _isStopped = true;
  int _reconnectAttempt = 0;

  void start() {
    if (!_isStopped && (_subscription != null || _isConnecting)) {
      return;
    }

    _isStopped = false;
    unawaited(_connect());
  }

  void stop() {
    _isStopped = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _isConnecting = false;
  }

  void dispose() {
    stop();
  }

  Future<void> _connect() async {
    if (_isStopped ||
        !_canConnect() ||
        _subscription != null ||
        _isConnecting) {
      return;
    }

    _isConnecting = true;
    final accessToken = await _authService.readAccessToken();
    if (_isStopped ||
        !_canConnect() ||
        accessToken == null ||
        accessToken.isEmpty) {
      _isConnecting = false;
      return;
    }

    final channel = WebSocketChannel.connect(_eventsUri(accessToken));

    try {
      await channel.ready;
    } on Object {
      _isConnecting = false;
      channel.sink.close();
      _scheduleReconnect();
      return;
    }

    if (_isStopped || !_canConnect()) {
      _isConnecting = false;
      channel.sink.close();
      return;
    }

    _isConnecting = false;
    _channel = channel;
    _reconnectAttempt = 0;
    _subscription = channel.stream.listen(
      _handleMessage,
      onError: (Object error, StackTrace stackTrace) => _handleClosed(),
      onDone: _handleClosed,
      cancelOnError: true,
    );
  }

  void _handleMessage(dynamic message) {
    if (_isStopped || !_canConnect()) {
      return;
    }

    if (message is String && message.isNotEmpty) {
      try {
        final decoded = jsonDecode(message);
        if (decoded is! Map<String, dynamic>) {
          return;
        }
      } catch (_) {
        return;
      }
    }

    _onEvent();
  }

  void _handleClosed() {
    _subscription = null;
    _channel = null;
    _isConnecting = false;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_isStopped || !_canConnect()) {
      return;
    }

    _reconnectTimer?.cancel();
    final nextDelaySeconds = (_reconnectAttempt + 1).clamp(1, 5);
    _reconnectAttempt = nextDelaySeconds;
    _reconnectTimer = Timer(Duration(seconds: nextDelaySeconds), () {
      if (_isStopped || !_canConnect()) {
        return;
      }
      unawaited(_connect());
    });
  }

  Uri _eventsUri(String accessToken) {
    final baseUri = Uri.parse(AppConfig.apiBaseUrl);
    final scheme = switch (baseUri.scheme.toLowerCase()) {
      'https' => 'wss',
      'wss' => 'wss',
      _ => 'ws',
    };

    return baseUri.replace(
      scheme: scheme,
      path: _path,
      queryParameters: {'accessToken': accessToken},
    );
  }
}
