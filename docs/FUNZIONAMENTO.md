# OmniMic — come funziona

Documento tecnico. Spiega cosa fa ogni file, come i dispositivi si trovano
fra loro e come viaggia l'audio. Presuppone che tu sappia leggere del codice,
non che tu conosca WebRTC.

---

## 1. L'idea in tre frasi

OmniMic è una chat vocale per una rete Wi-Fi locale, in cui **parla una
persona alla volta** e l'host decide chi.

Chi crea la stanza avvia un piccolo server dentro la propria app: gli altri
si collegano a lui. Il server però **non trasporta l'audio** — serve solo a
far conoscere i partecipanti fra loro e a tenere il conto di chi ha la parola.
L'audio va da dispositivo a dispositivo, diretto.

Non serve Internet, non serve aprire porte sul router, non serve niente di
installato da nessuna parte oltre all'app stessa.

---

## 2. Mappa dei file

```
lib/
├── main.dart                  avvio dell'app, niente logica
├── theme.dart                 colori, stili, pulsanti riutilizzabili
├── room_controller.dart       il cervello: audio + stato della stanza
├── net/
│   ├── room_code.dart         codice stanza <-> indirizzo IP
│   ├── lan_address.dart       qual è il nostro IP sul Wi-Fi
│   ├── signal_server.dart     il mini-server, gira solo nell'app dell'host
│   └── signal_client.dart     il collegamento al server (lo usano tutti)
└── screens/
    ├── home_screen.dart       username, crea stanza, entra
    └── room_screen.dart       la stanza: elenco, chi parla, comandi
```

La regola che tiene ordinato il progetto: **le schermate non sanno nulla di
rete**. Leggono i dati dal `RoomController` e chiamano i suoi comandi. Se un
giorno rifai l'interfaccia da zero, `lib/net/` e `room_controller.dart` non si
toccano.

---

## 3. Il codice stanza è l'indirizzo IP

Questa è la scelta di progetto più importante, ed è ciò che rende l'app
"plug and play".

Di solito un codice stanza è un'etichetta registrata su un server centrale,
che quando qualcuno la digita risponde "quella stanza sta all'indirizzo X".
Serve un server sempre acceso, e quindi un'infrastruttura.

In OmniMic il codice **è** l'indirizzo, scritto in forma breve:

```
192.168.1.42   →   0C0-80JA
```

Un indirizzo IPv4 sono quattro numeri da 0 a 255: 32 bit in tutto. Scritti in
base 32 diventano sette caratteri. Chi riceve il codice fa il conto al
contrario e ottiene l'indirizzo a cui collegarsi. Nessuno deve chiedere niente
a nessuno.

L'alfabeto è quello di Crockford — `0123456789ABCDEFGHJKMNPQRSTVWXYZ` — senza
`I`, `L`, `O` e `U`, perché al telefono si confondono con `1`, `0` e `V`. In
lettura le correggiamo comunque, quindi un codice dettato male funziona
ugualmente.

Lo stesso campo accetta anche un IP scritto per esteso: chi preferisce dire
"centonovantadue punto centosessantotto" invece di dettare lettere può farlo.

**Conseguenza da conoscere:** se il router assegna all'host un indirizzo
diverso (riavvio, cambio rete), il codice cambia. È corretto che sia così — il
codice descrive dove si trova l'host in quel momento.

---

## 4. Chi fa da server

`LanSignalServer` (`net/signal_server.dart`) si mette in ascolto sulla porta
**7788** di tutte le schede di rete del dispositivo. Essendo fissa, la porta
non ha bisogno di finire nel codice stanza.

Il dettaglio che semplifica tutto il resto: **l'host, appena avviato il
server, ci si collega come un client qualunque**, su `ws://127.0.0.1:7788`.

Da quel momento host e ospiti sono indistinguibili per il resto del programma.
Non esiste da nessuna parte un `if (sonoHost)` nella gestione dell'audio: c'è
solo un elenco di partecipanti, e uno di loro è marcato come host.

Il server riconosce l'host così: **il primo che si collega lo è**. Non è una
scorciatoia fragile — nessuno può conoscere il codice prima che la stanza
esista, e la stanza esiste solo dopo che l'host si è collegato.

---

## 5. I messaggi che viaggiano

Tutti in JSON, su WebSocket. Sono pochi ed è utile conoscerli a memoria.

### Dal client al server

| Messaggio | Chi può | Significato |
|---|---|---|
| `join` | tutti, una volta sola | mi presento, mi chiamo così |
| `signal` | tutti | passa questo pacchetto tecnico a quell'altro |
| `floor-request` | tutti | alzo la mano |
| `floor-cancel` | tutti | abbasso la mano |
| `floor-release` | chi parla | rinuncio alla parola |
| `floor-grant` | solo host | do la parola a quella persona |
| `floor-revoke` | solo host | tolgo la parola a chi ce l'ha |

I controlli sui permessi stanno **nel server**, non nell'interfaccia.
Nascondere un pulsante è una cortesia verso l'utente; impedire l'azione è
un'altra cosa, e va fatta dove la decisione viene presa.

### Dal server al client

| Messaggio | Quando |
|---|---|
| `welcome` | subito dopo `join`: ecco il tuo identificativo |
| `room` | a ogni cambiamento: la fotografia completa della stanza |
| `signal` | inoltro di un pacchetto tecnico da un altro partecipante |
| `closed` | l'host ha chiuso la stanza |
| `error` | qualcosa non andava nella richiesta |

Nota il criterio di `room`: invece di venti messaggini diversi (`è entrato
Tizio`, `Caio ha alzato la mano`, `ora parla Sempronio`) il server rimanda
sempre lo stato completo. I client non devono ricostruire niente: ridisegnano
quello che arriva. Costa qualche byte in più e toglie un'intera categoria di
bug, quelli in cui due dispositivi mostrano cose diverse.

---

## 6. Come nasce una connessione audio

Qui entra WebRTC. La sequenza, quando B entra in una stanza dove c'è già A:

1. Il server manda a entrambi la nuova fotografia della stanza.
2. Ognuno guarda l'elenco e nota che c'è qualcuno con cui non è ancora
   collegato (`_syncConnections`).
3. **Uno solo dei due fa la prima mossa.** Chi, lo decide il confronto
   alfabetico fra i due identificativi. Se si offrissero a vicenda, la
   negoziazione si romperebbe.
4. Chi offre crea una *offer*: una descrizione di che audio sa mandare e
   ricevere. La manda all'altro come `signal`.
5. L'altro risponde con una *answer*, stessa strada.
6. In parallelo entrambi scoprono i propri indirizzi di rete utilizzabili
   (i *candidati*) e se li scambiano, sempre come `signal`.
7. WebRTC prova le combinazioni, ne trova una che funziona, e da lì in poi
   **l'audio viaggia diretto**: il server non lo vede più passare.

Con N partecipanti ognuno tiene N-1 connessioni. Si chiama *mesh completa* ed
è la struttura più semplice possibile. Regge tranquillamente fino a una decina
di persone, che con un modello "parla uno alla volta" è più che sufficiente.

Il campo `iceServers` è **vuoto di proposito**: sulla rete locale i dispositivi
si vedono direttamente, non serve nessun server esterno per scoprire come
raggiungersi. È anche il motivo per cui l'app funziona senza Internet.

---

## 7. Come funziona la parola

Il microfono di ogni partecipante è **sempre collegato** alla connessione, ma
parte con `enabled = false`. Quando il server comunica che la parola è tua, il
controller mette `enabled = true`; quando passa a un altro, torna a `false`.

```dart
void _applyFloor() {
  final open = selfId != null && selfId == floorId;
  for (final track in _localStream?.getAudioTracks() ?? []) {
    track.enabled = open;
  }
}
```

Perché non aggiungere e togliere la traccia? Perché ogni modifica alla
struttura della connessione obbliga i due dispositivi a rinegoziare, con un
paio di secondi di silenzio. Attivare una traccia già presente è immediato: la
parola passa senza buchi.

Chi non ha la parola trasmette un flusso audio silenzioso, non trasmette il
tuo microfono. La differenza è importante: nessuno può sentirti.

---

## 8. I tre punti in cui WebRTC si rompe

Sono errori classici, tutti già gestiti nel codice. Se un domani lo modifichi,
ricordati che ci sono.

**Offerte incrociate.** Se entrambi i lati mandano un'offerta insieme, la
connessione finisce in uno stato incoerente. Soluzione: offre solo quello con
l'identificativo minore (`selfId!.compareTo(peer.id) < 0`).

**Candidati troppo presto.** I candidati di rete arrivano spesso prima della
descrizione remota, e in quel momento WebRTC li rifiuta. Soluzione:
`_earlyCandidates` li mette da parte e `_flushCandidates` li aggiunge appena
possibile.

**Operazioni intrecciate.** Due messaggi elaborati contemporaneamente sulla
stessa connessione la mandano fuori strada. Soluzione: `_serialize` mette in
fila le operazioni di ogni connessione, una alla volta.

---

## 9. Ciclo di vita

**Creazione stanza** — cerco il mio IP → chiedo il microfono → avvio il server
→ mi collego a me stesso → ricevo `welcome` → sono dentro, con la parola.

**Ingresso** — traduco codice o IP in indirizzo → chiedo il microfono → mi
collego all'host → ricevo `welcome` → alla prima `room` apro le connessioni
audio verso tutti.

**Uscita di un ospite** — il server se ne accorge dalla chiusura del socket,
lo toglie dall'elenco e manda la nuova fotografia; gli altri chiudono la
connessione verso di lui.

**Uscita dell'host** — la stanza non ha più un arbitro, quindi si chiude: tutti
ricevono `closed` e tornano alla schermata iniziale.

`_shutdown()` smonta tutto in ordine: ascoltatori, connessioni, microfono,
socket, server. Vale la pena rispettarlo — spegnere il microfono dopo aver
chiuso le connessioni lascia il LED acceso su alcuni portatili.

---

## 10. Limiti da conoscere

**Solo rete locale.** È una scelta, non una mancanza. Tutti devono stare sullo
stesso Wi-Fi.

**Isolamento client.** Alcuni router (soprattutto reti ospiti e Wi-Fi
pubbliche) impediscono ai dispositivi di parlarsi fra loro. Con quella
impostazione attiva OmniMic non può funzionare, e non c'è nulla da fare lato
app.

**Niente web.** Il mini-server usa `dart:io`, che nel browser non esiste. Le
piattaforme supportate sono Windows e Android.

**Schermo spento su Android.** Il sistema sospende l'app dopo qualche minuto e
l'audio si interrompe. Serve un *foreground service*, che è un pezzo di codice
Kotlin non ancora presente.

**Stanze in memoria.** Chiudere l'app dell'host cancella la stanza. Non è un
problema da risolvere: è quello che ci si aspetta.

**Nessuna cifratura del segnale.** I messaggi di coordinamento viaggiano in
chiaro sulla rete locale. L'audio invece è cifrato sempre: WebRTC non permette
di trasmetterlo altrimenti.
