# Cinema: Disponibilità & Posti

App Android **non ufficiale** per chi vuole solo sapere due cose, in fretta: *cosa danno oggi* e *quanti posti sono ancora liberi*. Niente account, niente pagamenti, niente prenotazioni: solo programmazione e mappa posti, prese dagli stessi dati già pubblici sui siti ufficiali.

Nata per risolvere due fastidi delle app ufficiali: l'etichetta "oggi" che a volte resta bloccata su ieri dopo la mezzanotte, e i tempi di caricamento della mappa posti - lenti non perché l'endpoint dei posti sia lento, ma perché l'app/sito ufficiale avviano l'intero flusso di prenotazione (ordine, pagamento, concessioni) prima ancora di mostrarti i posti liberi. Questa app salta dritta al punto.

## Cosa fa

- Scegli il tuo cinema preferito da una lista ricercabile per nome, catena o città (o più di uno, e passa dall'uno all'altro dalle impostazioni)
- Vedi gli spettacoli divisi per giorno, con locandina e orari
- Apri uno spettacolo e vedi subito la mappa posti: liberi, occupati, riservati, accessibilità - con legenda
- Da lì puoi cambiare giorno o orario senza tornare indietro alla lista film
- Un tasto ti manda alla pagina ufficiale se vuoi comprare davvero il biglietto
- Ti avvisa in automatico quando è disponibile una versione più recente (l'app non passa da nessuno store)

## Cinema supportati

| Catena | Copertura |
|---|---|
| The Space Cinema | 35 sale in tutta Italia |
| UCI Cinemas | 33 sale in tutta Italia |
| Cinema indipendenti sulla piattaforma "18tickets.net" | RedCarpet Cinema (Monopoli), Multicinema Galleria (Bari), Anteo spazioCinema (Lombardia), Circuito Cinema (Bologna, Roma, Napoli, Firenze, Torino), Pop Up Cinema (Bologna), Multisala Impero (Varese), Multisala Massimo (Lecce), Cinemazero (Pordenone), altri cinema indipendenti nel Lazio (Roma, Rieti, Aprilia, Latina, Tarquinia), in Veneto (Padova, Vicenza, Venezia, Verona), a Genova, Trento, Udine, Napoli, Bergamo e in altre città sparse (Taranto, Ancona, Fabriano, Palermo, Sassari, Torino, Gavirate, Belluno, Mercogliano, Ladispoli) |
| Notorious Cinemas, Giometti Cinema e Il Regno del Cinema (piattaforma "Webtic") | Notorious: 8 sale (Sesto San Giovanni, Rovigo, Gloria e Merlata Bloom Milano, Cagliari, Ferrara, Sinalunga, Curno). Giometti: 11 sale in Marche/Toscana/Emilia-Romagna (Pesaro, Riccione, Ancona, Fano, Rimini, Matelica, Prato, Jesi, Porto Sant'Elpidio, Senigallia, Tolentino). Il Regno del Cinema: 6 sale a Brescia, Crema e Milano (Multisala OZ, Portanova, Colosseo, Eliseo, Cinema Sociale, Cinema Moretto) |

Ognuna di queste catene parla un'API diversa (alcune un JSON pulito, altre solo HTML/SVG server-renderizzato) - vedi `PROJECT_NOTES.md` (locale, non versionato) per i dettagli del reverse engineering di ciascuna.

**Manca il tuo cinema?** Segnalalo con [questo form](https://forms.gle/ZvtR5KVo3nEwKaGP9).

## Com'è fatta

Flutter, nessun backend proprio: l'app chiama direttamente le API/i siti pubblici delle catene supportate.

- **Stato**: Riverpod (`flutter_riverpod`), cache in-memory con TTL brevi - niente persistenza locale oltre al cinema preferito (`shared_preferences`)
- **Rete**: `dio`, un client per catena
- **Routing**: `go_router`
- **Un'astrazione, quattro implementazioni**: ogni catena implementa la stessa `ChainApi` (`getShowingDates`/`getFilmsForDay`/`getSeatMap`); schermate e provider non sanno mai con quale catena stanno parlando. Aggiungere una nuova catena (o un nuovo cinema indipendente sulla stessa piattaforma) è una nuova classe più una riga nel registro, senza toccare l'interfaccia utente

## Sviluppo

```bash
flutter pub get
flutter test
flutter run          # debug, su emulatore o device connesso
flutter build apk --release
```

## Disclaimer

App non ufficiale, senza alcun legame con The Space Cinema, Vue International, UCI Cinemas o con nessuno dei cinema indipendenti elencati sopra. Non gestisce account, pagamenti, biglietti o prenotazioni: mostra soltanto programmazione e disponibilità posti, dati già pubblicamente visibili sui siti ufficiali.
