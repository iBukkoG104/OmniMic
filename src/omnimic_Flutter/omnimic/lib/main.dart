// -----------------------------------------------------------------------------
// OmniMic - avvio
// -----------------------------------------------------------------------------
// Chat vocale su rete locale con gestione della parola.
// Chi crea la stanza fa anche da server: non serve nessuna infrastruttura,
// nessuna porta da aprire, nemmeno una connessione a Internet.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OmniMicApp());
}

class OmniMicApp extends StatelessWidget {
  const OmniMicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OmniMic',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}
