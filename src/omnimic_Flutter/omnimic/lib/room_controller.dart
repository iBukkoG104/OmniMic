// -----------------------------------------------------------------------------
// OmniMic - controller della stanza
// -----------------------------------------------------------------------------
// E' il cuore dell'applicazione. Tiene insieme tre cose:
//
//   * la connessione al server di segnalazione (che per l'host e' il suo);
//   * una connessione audio diretta verso ogni altro partecipante;
//   * lo stato della parola: chi ce l'ha, chi l'ha chiesta.
//
// L'interfaccia non fa altro che leggere questi dati e chiamare i comandi in
// fondo al file. Ogni volta che qualcosa cambia chiamiamo notifyListeners()
// e le schermate si ridisegnano da sole.
// -----------------------------------------------------------------------------

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'net/lan_address.dart';
import 'net/room_code.dart';
import 'net/signal_client.dart';
import 'net/signal_server.dart';

/// Una persona nella stanza, come la vede l'interfaccia.
class Participant {
  const Participant({
    required this.id,
    required this.name,
    required this.requesting,
  });

  final String id;
  final String name;
  final bool requesting;
}

class RoomController extends ChangeNotifier {
  final SignalClient _signal = SignalClient();

  /// Presente solo se siamo noi a ospitare la stanza.
  LanSignalServer? _server;

  /// Una connessione audio per ogni altro partecipante.
  /// Il valore e' una Future cosi' due richieste contemporanee aspettano
  /// la stessa creazione invece di farne due.
  final Map<String, Future<RTCPeerConnection>> _connections = {};
  final Map<String, RTCVideoRenderer> _renderers = {};
  final Map<String, List<RTCIceCandidate>> _earlyCandidates = {};
  final Map<String, Future<void>> _queues = {};

  MediaStream? _localStream;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  // Stato leggibile dall'interfaccia.
  String? selfId;
  String? hostId;
  String? floorId;
  String? hostAddress;
  String? roomCode;
  String? error;
  bool inRoom = false;
  bool ownsServer = false;
  List<Participant> participants = const [];

  bool get isHost => selfId != null && selfId == hostId;
  bool get hasFloor => selfId != null && selfId == floorId;
  bool get isRequesting =>
      participants.any((p) => p.id == selfId && p.requesting);
  Map<String, RTCVideoRenderer> get renderers => _renderers;

  /// Sulla rete locale bastano i candidati "host", cioe' gli indirizzi delle
  /// schede di rete: i due dispositivi si vedono direttamente. Niente STUN,
  /// niente TURN, nessun bisogno di Internet.
  static const Map<String, dynamic> _rtcConfig = {
    'iceServers': <Map<String, dynamic>>[],
    'sdpSemantics': 'unified-plan',
  };

  // ------------------------------------------------------------------ ingresso

  /// Crea una stanza: avvia il mini-server e ci si collega come primo membro.
  Future<bool> createRoom({required String username}) async {
    error = null;

    final address = await findLanAddress();
    if (address == null) {
      return _fail('Nessuna rete locale rilevata. Collegati al Wi-Fi e riprova.');
    }

    if (!await _openMicrophone()) return false;

    final server = LanSignalServer();
    try {
      await server.start();
    } on SignalServerBusy {
      await _shutdown();
      return _fail(
        'La porta $kSignalPort e\' occupata: forse OmniMic e\' gia\' aperto.',
      );
    } catch (_) {
      await _shutdown();
      return _fail('Impossibile avviare la stanza su questo dispositivo.');
    }

    _server = server;
    ownsServer = true;
    hostAddress = address;
    roomCode = encodeAddress(address);

    final connected =
        await _connect(Uri.parse('ws://127.0.0.1:$kSignalPort'), username);
    if (!connected) await _shutdown();
    return connected;
  }

  /// Entra in una stanza esistente. [codeOrAddress] accetta sia il codice
  /// a sette caratteri sia un indirizzo IP scritto per esteso.
  Future<bool> joinRoom({
    required String username,
    required String codeOrAddress,
  }) async {
    error = null;

    final address = resolveAddress(codeOrAddress);
    if (address == null) {
      return _fail('Codice o indirizzo non valido.');
    }

    if (!await _openMicrophone()) return false;

    hostAddress = address;
    roomCode = encodeAddress(address);

    final connected =
        await _connect(Uri.parse('ws://$address:$kSignalPort'), username);
    if (!connected) await _shutdown();
    return connected;
  }

  Future<bool> _connect(Uri uri, String username) async {
    try {
      await _signal.connect(uri);
    } catch (_) {
      return _fail(
        'Host non raggiungibile a $hostAddress.\n'
        'Verifica che sia sulla stessa rete Wi-Fi e che la stanza sia aperta.',
      );
    }

    _subscription = _signal.messages.listen(_onMessage);
    _signal.send({'type': 'join', 'name': username});
    return true;
  }

  Future<bool> _openMicrophone() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.microphone.request();
        if (!status.isGranted) {
          return _fail('Permesso microfono negato.');
        }
      }

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });

      // Si entra sempre col microfono chiuso: lo apre solo chi ha la parola.
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = false;
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        await Helper.setSpeakerphoneOn(true);
      }
      return true;
    } catch (_) {
      return _fail('Microfono non disponibile su questo dispositivo.');
    }
  }

  bool _fail(String message) {
    error = message;
    notifyListeners();
    return false;
  }

  // ------------------------------------------------------- messaggi in arrivo

  void _onMessage(Map<String, dynamic> message) {
    switch (message['type']) {
      case 'welcome':
        selfId = message['self'] as String?;
        inRoom = true;
        notifyListeners();
        break;

      case 'room':
        _applySnapshot(message);
        break;

      case 'signal':
        final from = message['from'] as String;
        final payload = message['payload'] as Map<String, dynamic>;
        _serialize(from, () => _onSignal(from, payload));
        break;

      case 'closed':
        error = 'La stanza e\' stata chiusa dall\'host.';
        inRoom = false;
        notifyListeners();
        break;

      case 'disconnected':
        if (inRoom) {
          error = 'Connessione con l\'host persa.';
          inRoom = false;
          notifyListeners();
        }
        break;

      case 'error':
        error = message['message'] as String?;
        notifyListeners();
        break;
    }
  }

  void _applySnapshot(Map<String, dynamic> message) {
    hostId = message['host'] as String?;
    floorId = message['floor'] as String?;
    participants = (message['peers'] as List)
        .cast<Map<String, dynamic>>()
        .map((p) => Participant(
              id: p['id'] as String,
              name: p['name'] as String,
              requesting: p['requesting'] as bool,
            ))
        .toList();

    _applyFloor();
    _syncConnections();
    notifyListeners();
  }

  /// Il nostro microfono e' aperto se e solo se abbiamo la parola.
  /// La traccia resta sempre collegata: attivarla e disattivarla non richiede
  /// di rinegoziare nulla, quindi il passaggio di parola e' istantaneo.
  void _applyFloor() {
    final open = selfId != null && selfId == floorId;
    final tracks = _localStream?.getAudioTracks() ?? <MediaStreamTrack>[];
    for (final track in tracks) {
      track.enabled = open;
    }
  }

  // ------------------------------------------------------------- rete audio

  /// Apre una connessione verso i nuovi arrivati e chiude quelle di chi esce.
  void _syncConnections() {
    if (selfId == null) return;
    final present = participants.map((p) => p.id).toSet();

    for (final peer in participants) {
      if (peer.id == selfId) continue;
      if (_connections.containsKey(peer.id)) continue;

      // Regola anti-collisione: la prima mossa la fa sempre quello con
      // l'identificativo alfabeticamente minore. Se si offrissero a vicenda
      // la negoziazione si romperebbe.
      final weOffer = selfId!.compareTo(peer.id) < 0;
      _connections[peer.id] = _createConnection(peer.id, offering: weOffer);
    }

    for (final id in _connections.keys.toList()) {
      if (!present.contains(id)) _closeConnection(id);
    }
  }

  Future<RTCPeerConnection> _peer(String id) {
    return _connections.putIfAbsent(
      id,
      () => _createConnection(id, offering: false),
    );
  }

  Future<RTCPeerConnection> _createConnection(
    String id, {
    required bool offering,
  }) async {
    final pc = await createPeerConnection(_rtcConfig);

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    _renderers[id] = renderer;

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _signal.send({
        'type': 'signal',
        'to': id,
        'payload': {'kind': 'ice', 'candidate': candidate.toMap()},
      });
    };

    pc.onTrack = (event) {
      if (event.streams.isEmpty) return;
      renderer.srcObject = event.streams.first;
      notifyListeners();
    };

    for (final track in _localStream!.getTracks()) {
      await pc.addTrack(track, _localStream!);
    }

    if (offering) {
      final offer = await pc.createOffer({'offerToReceiveAudio': true});
      await pc.setLocalDescription(offer);
      _signal.send({
        'type': 'signal',
        'to': id,
        'payload': {'kind': 'offer', 'sdp': offer.sdp, 'sdpType': offer.type},
      });
    }

    return pc;
  }

  Future<void> _onSignal(String from, Map<String, dynamic> payload) async {
    final pc = await _peer(from);

    switch (payload['kind']) {
      case 'offer':
        await pc.setRemoteDescription(RTCSessionDescription(
          payload['sdp'] as String,
          payload['sdpType'] as String,
        ));
        await _flushCandidates(from, pc);

        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        _signal.send({
          'type': 'signal',
          'to': from,
          'payload': {
            'kind': 'answer',
            'sdp': answer.sdp,
            'sdpType': answer.type,
          },
        });
        break;

      case 'answer':
        await pc.setRemoteDescription(RTCSessionDescription(
          payload['sdp'] as String,
          payload['sdpType'] as String,
        ));
        await _flushCandidates(from, pc);
        break;

      case 'ice':
        final map = payload['candidate'] as Map<String, dynamic>;
        final candidate = RTCIceCandidate(
          map['candidate'] as String?,
          map['sdpMid'] as String?,
          map['sdpMLineIndex'] as int?,
        );

        // I candidati arrivano spesso prima della descrizione remota:
        // in quel caso li mettiamo da parte e li aggiungiamo dopo.
        if (await pc.getRemoteDescription() == null) {
          _earlyCandidates.putIfAbsent(from, () => []).add(candidate);
        } else {
          await pc.addCandidate(candidate);
        }
        break;
    }
  }

  Future<void> _flushCandidates(String from, RTCPeerConnection pc) async {
    final queued = _earlyCandidates.remove(from);
    if (queued == null) return;
    for (final candidate in queued) {
      await pc.addCandidate(candidate);
    }
  }

  /// Le operazioni su una stessa connessione devono avvenire in fila indiana:
  /// due negoziazioni intrecciate la lasciano in uno stato incoerente.
  void _serialize(String id, Future<void> Function() task) {
    final previous = _queues[id] ?? Future<void>.value();
    _queues[id] = previous.then((_) => task()).catchError(
          (Object e) => debugPrint('OmniMic: errore sulla connessione $id - $e'),
        );
  }

  Future<void> _closeConnection(String id) async {
    final pending = _connections.remove(id);
    _queues.remove(id);
    _earlyCandidates.remove(id);

    final renderer = _renderers.remove(id);
    if (renderer != null) {
      renderer.srcObject = null;
      await renderer.dispose();
    }

    try {
      final pc = await pending;
      await pc?.close();
    } catch (_) {}

    notifyListeners();
  }

  // ------------------------------------------------------------------ comandi

  void requestFloor() => _signal.send({'type': 'floor-request'});
  void cancelRequest() => _signal.send({'type': 'floor-cancel'});
  void releaseFloor() => _signal.send({'type': 'floor-release'});
  void grantFloor(String id) =>
      _signal.send({'type': 'floor-grant', 'target': id});
  void revokeFloor() => _signal.send({'type': 'floor-revoke'});

  Future<void> leave() async {
    inRoom = false;
    await _shutdown();
    notifyListeners();
  }

  /// Smonta tutto nell'ordine giusto: ascoltatori, connessioni, microfono,
  /// socket e infine il server se eravamo noi a ospitare.
  Future<void> _shutdown() async {
    await _subscription?.cancel();
    _subscription = null;

    for (final id in _connections.keys.toList()) {
      await _closeConnection(id);
    }

    final tracks = _localStream?.getTracks() ?? <MediaStreamTrack>[];
    for (final track in tracks) {
      await track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;

    await _signal.dispose();

    await _server?.stop();
    _server = null;
    ownsServer = false;
  }

  @override
  void dispose() {
    _shutdown();
    super.dispose();
  }
}
