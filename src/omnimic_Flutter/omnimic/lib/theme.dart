// -----------------------------------------------------------------------------
// OmniMic - tema
// -----------------------------------------------------------------------------
// Tutti i colori dell'app stanno qui dentro. Se un domani vuoi cambiare
// aspetto, questo e' l'unico file da toccare.
//
// La logica cromatica e' quella di una console audio: fondo scuro e neutro,
// il rosso riservato a "microfono aperto", l'ambra a "richiesta in attesa".
// Nient'altro e' colorato, cosi' l'occhio va subito dove serve.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';

abstract final class Palette {
  static const background = Color(0xFF0F1216);
  static const panel = Color(0xFF171B21);
  static const panelHigh = Color(0xFF1E242C);
  static const line = Color(0xFF262D37);
  static const text = Color(0xFFE7EAEF);
  static const dim = Color(0xFF79818F);
  static const live = Color(0xFFD6453C);
  static const pending = Color(0xFFDFA23C);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    surface: Palette.background,
    primary: Palette.text,
    onPrimary: Palette.background,
    error: Palette.live,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.background,
    splashFactory: NoSplash.splashFactory,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: Palette.text, fontSize: 14, height: 1.45),
      bodySmall: TextStyle(color: Palette.dim, fontSize: 12.5, height: 1.4),
      titleMedium: TextStyle(
        color: Palette.text,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.panel,
      hintStyle: const TextStyle(color: Color(0xFF525A67)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: _fieldBorder(Palette.line),
      enabledBorder: _fieldBorder(Palette.line),
      focusedBorder: _fieldBorder(const Color(0xFF3D4652)),
      errorBorder: _fieldBorder(Palette.live),
      focusedErrorBorder: _fieldBorder(Palette.live),
    ),
  );
}

OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: color),
    );

/// Etichetta piccola e spaziata sopra i campi e le sezioni.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Palette.dim,
            fontSize: 10.5,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

/// Pulsante pieno, quello dell'azione principale di ogni schermata.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.background = Palette.text,
    this.foreground = Palette.background,
    this.height = 46,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Color background;
  final Color foreground;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: const Color(0xFF3A414C),
          disabledForegroundColor: Palette.dim,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        onPressed: onPressed,
        child: busy
            ? SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            : Text(label),
      ),
    );
  }
}

/// Pulsante con solo il bordo, per le azioni secondarie.
class OutlineButton extends StatelessWidget {
  const OutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 50,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Palette.live : Palette.text;
    return SizedBox(
      height: height,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: danger ? Palette.live : Palette.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}
