// -----------------------------------------------------------------------------
// OmniMic - mini-server di segnalazione
// -----------------------------------------------------------------------------
// Questo pezzo gira DENTRO l'app di chi crea la stanza.
//
// Non trasporta audio: l'audio viaggia direttamente da dispositivo a
// dispositivo. Il server serve a tre cose soltanto:
//
//   1. far scoprire ai partecipanti chi altro c'e' nella stanza;
//   2. passare da uno all'altro i messaggi tecnici con cui WebRTC si accorda
//      (le "offerte" e i "candidati di rete");
//   3. tenere il conto di chi ha la parola, perche' quella decisione deve
//      essere una sola per tutti.
//
// L'app dell'host, subito dopo aver avviato questo server, ci si collega come
// un client qualsiasi. Cosi' tutto il resto del programma non deve mai chiedersi
// "sono l'host o un ospite?": la logica e' identica per tutti.
// -----------------------------------------------------------------------------

import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Porta fissa. Essendo fissa, non serve scriverla nel codice stanza.
const int kSignalPort = 7788;

/// La porta e' gia' occupata (di solito: un'altra copia di OmniMic aperta).
class SignalServerBusy implements Exception {}

class _Guest {
  _Guest(this.id, this.name, this.socket);

  final String id;
  final String name;
  final WebSocket socket;
  bool requesting = false;
}

class LanSignalServer {
  HttpServer? _http;
  final Map<String, _Guest> _guests = {};
  final Random _random = Random();

  String? _hostId;
  String? _floorId;

  bool get isRunning => _http != null;

  /// Mette il server in ascolto su tutte le schede di rete del dispositivo,
  /// cosi' risponde sia a 127.0.0.1 (l'host stesso) sia all'IP del Wi-Fi.
  Future<void> start() async {
    try {
      _http = await HttpServer.bind(InternetAddress.anyIPv4, kSignalPort);
    } on SocketException {
      throw SignalServerBusy();
    }
    _http!.listen(_onRequest, onError: (Object _) {});
  }

  /// Chiude la stanza: avvisa tutti e spegne il server.
  Future<void> stop() async {
    for (final guest in _guests.values.toList()) {
      _send(guest.socket, {'type': 'closed'});
      guest.socket.close();
    }
    _guests.clear();
    _hostId = null;
    _floorId = null;

    final http = _http;
    _http = null;
    await http?.close(force: true);
  }

  // --------------------------------------------------------------- connessioni

  void _onRequest(HttpRequest request) async {
    // Chi apre l'indirizzo col browser riceve solo una riga di cortesia:
    // e' utile per verificare al volo che il server sia raggiungibile.
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('OmniMic attivo')
        ..close();
      return;
    }

    try {
      final socket = await WebSocketTransformer.upgrade(request);
      _accept(socket);
    } catch (_) {
      // Handshake fallito: il client se ne accorge da solo.
    }
  }

  void _accept(WebSocket socket) {
    // Finche' vale null, questa connessione non si e' ancora presentata.
    String? id;

    socket.listen(
      (Object? raw) {
        final message = _decode(raw);
        if (message == null) return;

        if (id == null) {
          id = _register(socket, message);
          return;
        }

        final guest = _guests[id];
        if (guest != null) _handle(guest, message);
      },
      onDone: () => _remove(id),
      onError: (Object _) => _remove(id),
      cancelOnError: true,
    );
  }

  /// Primo messaggio di una connessione: deve essere una presentazione.
  String? _register(WebSocket socket, Map<String, dynamic> message) {
    if (message['type'] != 'join') {
      _send(socket, {'type': 'error', 'message': 'Presentazione mancante'});
      return null;
    }

    final name = (message['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) {
      _send(socket, {'type': 'error', 'message': 'Username mancante'});
      return null;
    }

    final id = _newId();
    _guests[id] = _Guest(id, name, socket);

    // Il primo a collegarsi e' per forza l'app che ospita: nessuno puo'
    // conoscere il codice prima che la stanza esista.
    if (_hostId == null) {
      _hostId = id;
      _floorId = id; // l'host parte con la parola
    }

    _send(socket, {'type': 'welcome', 'self': id});
    _broadcast();
    return id;
  }

  void _remove(String? id) {
    if (id == null) return;
    final guest = _guests.remove(id);
    if (guest == null) return;

    if (_floorId == id) _floorId = null;

    // Se se ne va l'host, la stanza non ha piu' un arbitro: si chiude.
    if (id == _hostId) {
      stop();
      return;
    }

    _broadcast();
  }

  // ------------------------------------------------------------------ messaggi

  void _handle(_Guest sender, Map<String, dynamic> message) {
    switch (message['type']) {
      // Inoltro cieco fra due partecipanti: il server non guarda il contenuto.
      case 'signal':
        final target = _guests[message['to']];
        if (target != null) {
          _send(target.socket, {
            'type': 'signal',
            'from': sender.id,
            'payload': message['payload'],
          });
        }
        break;

      case 'floor-request':
        sender.requesting = true;
        _broadcast();
        break;

      case 'floor-cancel':
        sender.requesting = false;
        _broadcast();
        break;

      // Solo l'host assegna la parola.
      case 'floor-grant':
        if (sender.id != _hostId) break;
        final target = message['target'] as String?;
        if (target == null || !_guests.containsKey(target)) break;
        _floorId = target;
        _guests[target]!.requesting = false;
        _broadcast();
        break;

      // Solo l'host la toglie...
      case 'floor-revoke':
        if (sender.id != _hostId) break;
        _floorId = null;
        _broadcast();
        break;

      // ...ma chi sta parlando puo' sempre rinunciarci da solo.
      case 'floor-release':
        if (_floorId != sender.id) break;
        _floorId = null;
        _broadcast();
        break;
    }
  }

  /// Invece di mille messaggini diversi, a ogni cambiamento mandiamo a tutti
  /// la stessa fotografia completa della stanza. I client si limitano a
  /// ridisegnare cio' che vedono.
  void _broadcast() {
    final snapshot = jsonEncode({
      'type': 'room',
      'host': _hostId,
      'floor': _floorId,
      'peers': _guests.values
          .map((g) => {'id': g.id, 'name': g.name, 'requesting': g.requesting})
          .toList(),
    });

    for (final guest in _guests.values) {
      try {
        guest.socket.add(snapshot);
      } catch (_) {
        // Connessione gia' caduta: se ne occupa onDone.
      }
    }
  }

  // ------------------------------------------------------------------ utilita'

  void _send(WebSocket socket, Map<String, dynamic> message) {
    try {
      socket.add(jsonEncode(message));
    } catch (_) {}
  }

  Map<String, dynamic>? _decode(Object? raw) {
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _newId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(8, (_) => chars[_random.nextInt(chars.length)]).join();
  }
}
