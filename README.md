# Cinema: Disponibilità & Posti

App Android **non ufficiale** per chi vuole solo sapere due cose, in fretta: *cosa danno oggi* e *quanti posti sono ancora liberi*. Niente account, niente pagamenti, niente prenotazioni: solo programmazione e mappa posti, prese dagli stessi dati già pubblici sui siti ufficiali.

Nata per risolvere due fastidi delle app ufficiali: l'etichetta "oggi" che a volte resta bloccata su ieri dopo la mezzanotte, e i tempi di caricamento della mappa posti - lenti non perché l'endpoint dei posti sia lento, ma perché l'app/sito ufficiale avviano l'intero flusso di prenotazione (ordine, pagamento, concessioni) prima ancora di mostrarti i posti liberi. Questa app salta dritta al punto.

## Cosa fa

- Scegli il tuo cinema preferito da una lista ricercabile (o più di uno, e passa dall'uno all'altro dalle impostazioni)
- Vedi gli spettacoli divisi per giorno, con locandina e orari
- Apri uno spettacolo e vedi subito la mappa posti: liberi, occupati, riservati, accessibilità - con legenda
- Da lì puoi cambiare giorno o orario senza tornare indietro alla lista film
- Un tasto ti manda alla pagina ufficiale se vuoi comprare davvero il biglietto

## Cinema supportati

| Catena | Copertura |
|---|---|
| The Space Cinema | 33 sale in tutta Italia |
| UCI Cinemas | 33 sale in tutta Italia |
| RedCarpet Cinema (Monopoli) e Multicinema Galleria (Bari) | cinema indipendenti sulla stessa piattaforma "18tickets.net" |

Ognuna di queste catene parla un'API diversa (alcune un JSON pulito, altre solo HTML/SVG server-renderizzato) - vedi `PROJECT_NOTES.md` (locale, non versionato) per i dettagli del reverse engineering di ciascuna.

## Com'è fatta

Flutter, nessun backend proprio: l'app chiama direttamente le API/i siti pubblici delle catene supportate.

- **Stato**: Riverpod (`flutter_riverpod`), cache in-memory con TTL brevi - niente persistenza locale oltre al cinema preferito (`shared_preferences`)
- **Rete**: `dio`, un client per catena
- **Routing**: `go_router`
- **Un'astrazione, tre implementazioni**: ogni catena implementa la stessa `ChainApi` (`getShowingDates`/`getFilmsForDay`/`getSeatMap`); schermate e provider non sanno mai con quale catena stanno parlando. Aggiungere una nuova catena (o un nuovo cinema indipendente sulla stessa piattaforma) è una nuova classe più una riga nel registro, senza toccare l'interfaccia utente

## Sviluppo

```bash
flutter pub get
flutter test
flutter run          # debug, su emulatore o device connesso
flutter build apk --release
```

## Disclaimer

App non ufficiale, senza alcun legame con The Space Cinema, Vue International, UCI Cinemas, RedCarpet Cinema o Multicinema Galleria. Non gestisce account, pagamenti, biglietti o prenotazioni: mostra soltanto programmazione e disponibilità posti, dati già pubblicamente visibili sui siti ufficiali.
