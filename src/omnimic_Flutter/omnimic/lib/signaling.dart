import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Sottile strato sopra il WebSocket: incapsula JSON in entrata e in uscita.
/// Non sa nulla di WebRTC nÃ© di stanze.
class SignalingClient {
  WebSocketChannel? _channel;
  final _incoming = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _incoming.stream;

  Future<void> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready; // lancia eccezione se il server non risponde
    _channel = channel;

    channel.stream.listen(
          (raw) {
        try {
          final decoded = jsonDecode(raw as String);
          if (decoded is Map<String, dynamic>) _incoming.add(decoded);
        } catch (_) {
          // messaggio malformato: ignorato
        }
      },
      onDone: () => _incoming.add({'type': 'disconnected'}),
      onError: (_) => _incoming.add({'type': 'disconnected'}),
    );
  }

  void send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  Future<void> dispose() async {
    await _channel?.sink.close();
    await _incoming.close();
  }
}