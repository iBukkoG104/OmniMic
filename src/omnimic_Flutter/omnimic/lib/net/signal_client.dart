// -----------------------------------------------------------------------------
// OmniMic - client di segnalazione
// -----------------------------------------------------------------------------
// Strato sottilissimo sopra il WebSocket: converte le mappe Dart in JSON in
// uscita e viceversa in entrata. Non sa nulla di stanze ne' di WebRTC.
//
// Lo usano tutti allo stesso modo, host compreso: l'host si collega al proprio
// server su 127.0.0.1.
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class SignalClient {
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _incoming =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Messaggi in arrivo dal server, gia' decodificati.
  Stream<Map<String, dynamic>> get messages => _incoming.stream;

  /// Apre la connessione. Solleva un'eccezione se l'host non risponde
  /// entro il tempo limite: senza timeout l'app resterebbe appesa.
  Future<void> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready.timeout(const Duration(seconds: 6));
    _channel = channel;

    channel.stream.listen(
      (Object? raw) {
        if (raw is! String) return;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) _incoming.add(decoded);
        } catch (_) {
          // Messaggio malformato: ignorato.
        }
      },
      onDone: () => _emit({'type': 'disconnected'}),
      onError: (Object _) => _emit({'type': 'disconnected'}),
    );
  }

  void send(Map<String, dynamic> message) {
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    if (!_incoming.isClosed) await _incoming.close();
  }

  void _emit(Map<String, dynamic> message) {
    if (!_incoming.isClosed) _incoming.add(message);
  }
}
