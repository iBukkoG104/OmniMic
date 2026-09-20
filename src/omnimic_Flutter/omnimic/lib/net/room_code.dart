// -----------------------------------------------------------------------------
// OmniMic - codice stanza
// -----------------------------------------------------------------------------
// In OmniMic non esiste un registro delle stanze da qualche parte in rete:
// il codice stanza E' l'indirizzo IP dell'host, scritto in forma breve.
//
//   192.168.1.42  ->  0C0-80JA   (esempio)
//
// Un indirizzo IPv4 sono 4 numeri da 0 a 255, cioe' 32 bit in tutto.
// Scritti in base 32 diventano 7 caratteri. Chi riceve il codice lo
// riconverte nell'indirizzo e si collega: nessun server intermedio.
//
// L'alfabeto e' quello di Crockford: mancano I, L, O e U perche' al telefono
// si confondono con 1, 0 e V. Se qualcuno le scrive lo stesso, le correggiamo
// noi in fase di lettura.
// -----------------------------------------------------------------------------

const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Trasforma "192.168.1.42" nel codice leggibile "XXX-XXXX".
String encodeAddress(String address) {
  final parts = address.split('.');

  // I quattro numeri diventano un unico valore: 192*256^3 + 168*256^2 + ...
  var value = 0;
  for (final part in parts) {
    value = value * 256 + (int.tryParse(part) ?? 0);
  }

  // Lo riscriviamo in base 32, partendo dall'ultima cifra.
  final digits = List<String>.filled(7, '0');
  for (var i = 6; i >= 0; i--) {
    digits[i] = _alphabet[value % 32];
    value = value ~/ 32;
  }

  final code = digits.join();
  return '${code.substring(0, 3)}-${code.substring(3)}';
}

/// Accetta sia un codice stanza sia un indirizzo IP scritto a mano.
/// Restituisce l'indirizzo a cui collegarsi, oppure null se l'input non ha senso.
String? resolveAddress(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return null;

  // Caso semplice: l'utente ha scritto direttamente un IP.
  if (isIpv4(raw)) return raw;

  // Altrimenti proviamo a leggerlo come codice: via spazi, trattini e minuscole.
  var cleaned = raw.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');

  // Correzione degli errori di trascrizione tipici.
  cleaned = cleaned
      .replaceAll('I', '1')
      .replaceAll('L', '1')
      .replaceAll('O', '0')
      .replaceAll('U', 'V');

  if (cleaned.length != 7) return null;

  var value = 0;
  for (var i = 0; i < cleaned.length; i++) {
    final digit = _alphabet.indexOf(cleaned[i]);
    if (digit < 0) return null;
    value = value * 32 + digit;
  }

  // Sette caratteri possono esprimere piu' di 32 bit: se il valore sfora,
  // il codice non corrisponde a nessun indirizzo valido.
  if (value > 4294967295) return null;

  final a = value ~/ 16777216;
  final b = (value ~/ 65536) % 256;
  final c = (value ~/ 256) % 256;
  final d = value % 256;
  return '$a.$b.$c.$d';
}

/// Vero se la stringa e' un indirizzo IPv4 ben formato.
bool isIpv4(String value) {
  final parts = value.split('.');
  if (parts.length != 4) return false;
  for (final part in parts) {
    if (part.isEmpty || part.length > 3) return false;
    final number = int.tryParse(part);
    if (number == null || number < 0 || number > 255) return false;
  }
  return true;
}
