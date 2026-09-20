// -----------------------------------------------------------------------------
// OmniMic - schermata iniziale
// -----------------------------------------------------------------------------
// Due sole strade: creare una stanza (e diventare host) oppure entrare in una
// stanza altrui scrivendo il codice o l'indirizzo IP.
//
// L'username viene ricordato fra un avvio e l'altro: chi apre l'app la seconda
// volta trova il campo gia' compilato e deve solo premere un pulsante.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../room_controller.dart';
import '../theme.dart';
import 'room_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _code = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restoreUsername();
  }

  Future<void> _restoreUsername() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _name.text = prefs.getString('username') ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  /// Unico percorso di ingresso, usato sia per creare sia per entrare.
  /// [code] null significa "crea una stanza nuova".
  Future<void> _enter({String? code}) async {
    final username = _name.text.trim();

    if (username.isEmpty) {
      setState(() => _error = 'Scegli un username.');
      return;
    }
    if (code != null && code.isEmpty) {
      setState(() => _error = 'Inserisci il codice della stanza.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', username);

    final controller = RoomController();
    final ok = code == null
        ? await controller.createRoom(username: username)
        : await controller.joinRoom(username: username, codeOrAddress: code);

    if (!mounted) {
      controller.dispose();
      return;
    }

    setState(() => _busy = false);

    if (!ok) {
      setState(() => _error = controller.error);
      controller.dispose();
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RoomScreen(controller: controller)),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Wordmark(),
                const SizedBox(height: 36),

                const FieldLabel('Username'),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: 'Come ti vedono gli altri',
                  ),
                ),
                const SizedBox(height: 26),

                PrimaryButton(
                  label: 'Crea una stanza',
                  busy: _busy,
                  onPressed: _busy ? null : () => _enter(),
                ),
                const SizedBox(height: 8),
                Text(
                  'Il tuo dispositivo fara\' da punto di incontro. '
                  'Gli altri devono essere sulla stessa rete Wi-Fi.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),

                Row(
                  children: [
                    const Expanded(child: Divider(color: Palette.line, height: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'oppure',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const Expanded(child: Divider(color: Palette.line, height: 1)),
                  ],
                ),
                const SizedBox(height: 24),

                const FieldLabel('Codice stanza o indirizzo IP'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _code,
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [UpperCaseFormatter()],
                        onSubmitted: (value) =>
                            _busy ? null : _enter(code: value.trim()),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 15,
                          letterSpacing: 1.5,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'XXX-XXXX',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlineButton(
                      label: 'Entra',
                      onPressed:
                          _busy ? null : () => _enter(code: _code.text.trim()),
                    ),
                  ],
                ),

                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Palette.live.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Palette.live,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Converte in maiuscolo mentre si scrive: i codici sono sempre maiuscoli.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 3, height: 22, color: Palette.live),
            const SizedBox(width: 10),
            const Text(
              'OMNIMIC',
              style: TextStyle(
                color: Palette.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 13),
          child: Text(
            'Chat vocale sulla rete locale',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
