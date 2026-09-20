// -----------------------------------------------------------------------------
// OmniMic - indirizzo sulla rete locale
// -----------------------------------------------------------------------------
// Per fare da host serve sapere quale indirizzo IP abbiamo sul Wi-Fi.
// Sembra banale, ma un PC Windows ne ha spesso cinque o sei: quello vero del
// Wi-Fi, piu' quelli finti creati da Hyper-V, VirtualBox, VPN, WSL, Docker.
// Se scegliamo quello sbagliato, il codice stanza porta gli altri nel vuoto.
//
// Qui scartiamo le schede virtuali dal nome e teniamo solo gli indirizzi
// privati, cioe' quelli che un router domestico assegna davvero.
// -----------------------------------------------------------------------------

import 'dart:io';

/// Frammenti di nome che tradiscono una scheda di rete virtuale.
const List<String> _virtualHints = [
  'loopback',
  'vethernet',
  'virtualbox',
  'vmware',
  'hyper-v',
  'docker',
  'wsl',
  'tailscale',
  'zerotier',
  'radmin',
  'bluetooth',
  'tap',
  'tun',
];

/// Restituisce l'indirizzo IPv4 del dispositivo sulla rete locale,
/// oppure null se non e' collegato a nessuna rete utilizzabile.
Future<String?> findLanAddress() async {
  List<NetworkInterface> interfaces;
  try {
    interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
  } catch (_) {
    return null;
  }

  final candidates = <String>[];
  for (final interface in interfaces) {
    final name = interface.name.toLowerCase();
    final isVirtual = _virtualHints.any((hint) => name.contains(hint));
    if (isVirtual) continue;

    for (final address in interface.addresses) {
      if (_isPrivate(address.address)) {
        candidates.add(address.address);
      }
    }
  }

  if (candidates.isEmpty) return null;

  // Se ce n'e' piu' di uno preferiamo 192.168.x.x, che e' la rete di casa
  // nella stragrande maggioranza dei router.
  candidates.sort((a, b) => _priority(a).compareTo(_priority(b)));
  return candidates.first;
}

int _priority(String address) {
  if (address.startsWith('192.168.')) return 0;
  if (address.startsWith('10.')) return 1;
  return 2;
}

/// Gli indirizzi privati sono 192.168.x.x, 10.x.x.x e da 172.16 a 172.31.
bool _isPrivate(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return false;

  final first = int.tryParse(parts[0]) ?? -1;
  final second = int.tryParse(parts[1]) ?? -1;

  if (first == 192 && second == 168) return true;
  if (first == 10) return true;
  if (first == 172 && second >= 16 && second <= 31) return true;
  return false;
}
