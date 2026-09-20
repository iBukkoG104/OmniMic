// -----------------------------------------------------------------------------
// OmniMic - schermata della stanza
// -----------------------------------------------------------------------------
// Tre zone, dall'alto in basso:
//
//   * intestazione: il codice da dettare agli altri e il pulsante per uscire;
//   * striscia "in onda": chi sta parlando in questo momento;
//   * elenco dei partecipanti, con i comandi dell'host su ogni riga.
//
// In fondo, il pulsante grande cambia da solo: chiedi la parola / annulla la
// richiesta / rilascia la parola, a seconda della situazione.
// -----------------------------------------------------------------------------

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../room_controller.dart';
import '../theme.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.controller});

  final RoomController controller;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  /// Il controller ci avvisa a ogni cambiamento. Se siamo usciti dalla stanza
  /// torniamo indietro, altrimenti ridisegniamo e basta.
  void _onChange() {
    if (!mounted) return;

    if (!widget.controller.inRoom) {
      final reason = widget.controller.error;
      Navigator.of(context).pop();
      if (reason != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(reason)));
      }
      return;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final speaker = controller.participants
        .firstWhereOrNull((p) => p.id == controller.floorId);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _Header(
                  code: controller.roomCode ?? '-',
                  address: controller.hostAddress,
                  isHost: controller.isHost,
                  onLeave: controller.leave,
                ),
                _OnAirStrip(
                  speakerName: speaker?.name,
                  youSpeak: controller.hasFloor,
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    itemCount: controller.participants.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final person = controller.participants[index];
                      return _ParticipantRow(
                        participant: person,
                        isSelf: person.id == controller.selfId,
                        isHost: person.id == controller.hostId,
                        hasFloor: person.id == controller.floorId,
                        showHostControls: controller.isHost,
                        onGrant: () => controller.grantFloor(person.id),
                        onRevoke: controller.revokeFloor,
                      );
                    },
                  ),
                ),
                _ActionBar(controller: controller),
              ],
            ),

            // I renderer devono restare nell'albero dei widget perche' l'audio
            // remoto venga riprodotto. Occupano un pixel e sono invisibili.
            Positioned(
              left: 0,
              bottom: 0,
              child: Row(
                children: [
                  for (final renderer in controller.renderers.values)
                    SizedBox(width: 1, height: 1, child: RTCVideoView(renderer)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.code,
    required this.address,
    required this.isHost,
    required this.onLeave,
  });

  final String code;
  final String? address;
  final bool isHost;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Palette.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('Codice stanza'),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        code,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Palette.text,
                          fontFamily: 'monospace',
                          fontSize: 20,
                          letterSpacing: 3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      color: Palette.dim,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Copia il codice',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Codice copiato'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                if (address != null)
                  Text(
                    'oppure $address',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Palette.dim),
            onPressed: onLeave,
            child: Text(isHost ? 'Chiudi' : 'Esci'),
          ),
        ],
      ),
    );
  }
}

class _OnAirStrip extends StatelessWidget {
  const _OnAirStrip({required this.speakerName, required this.youSpeak});

  final String? speakerName;
  final bool youSpeak;

  @override
  Widget build(BuildContext context) {
    final live = speakerName != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      color: live ? Palette.live.withValues(alpha: 0.12) : Palette.panel,
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: live ? Palette.live : Palette.dim,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              live
                  ? (youSpeak ? 'Hai la parola' : 'In onda: $speakerName')
                  : 'Nessuno ha la parola',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: live ? Palette.text : Palette.dim,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.isSelf,
    required this.isHost,
    required this.hasFloor,
    required this.showHostControls,
    required this.onGrant,
    required this.onRevoke,
  });

  final Participant participant;
  final bool isSelf;
  final bool isHost;
  final bool hasFloor;
  final bool showHostControls;
  final VoidCallback onGrant;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: hasFloor ? Palette.live : Palette.line),
      ),
      child: Row(
        children: [
          Icon(
            hasFloor ? Icons.mic_rounded : Icons.mic_off_rounded,
            size: 17,
            color: hasFloor ? Palette.live : const Color(0xFF4C5563),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isSelf ? '${participant.name} (tu)' : participant.name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (isHost) const _Tag('host', Palette.dim),
          if (participant.requesting) ...[
            const SizedBox(width: 6),
            const _Tag('chiede', Palette.pending),
          ],
          if (showHostControls && !hasFloor) ...[
            const SizedBox(width: 8),
            _RowAction(label: 'Dai parola', onPressed: onGrant),
          ],
          if (showHostControls && hasFloor && !isSelf) ...[
            const SizedBox(width: 8),
            _RowAction(label: 'Togli', onPressed: onRevoke, danger: true),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          letterSpacing: 0.9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: danger ? Palette.live : Palette.text,
          side: BorderSide(color: danger ? Palette.live : Palette.line),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          textStyle: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.controller});

  final RoomController controller;

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final VoidCallback action;
    late final Color background;
    late final Color foreground;

    if (controller.hasFloor) {
      label = 'Rilascia la parola';
      action = controller.releaseFloor;
      background = Palette.live;
      foreground = Colors.white;
    } else if (controller.isRequesting) {
      label = 'Annulla richiesta';
      action = controller.cancelRequest;
      background = Palette.pending;
      foreground = Palette.background;
    } else {
      label = 'Chiedi la parola';
      action = controller.requestFloor;
      background = Palette.text;
      foreground = Palette.background;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration: const BoxDecoration(
        color: Palette.panelHigh,
        border: Border(top: BorderSide(color: Palette.line)),
      ),
      child: PrimaryButton(
        label: label,
        onPressed: action,
        background: background,
        foreground: foreground,
        height: 50,
      ),
    );
  }
}
