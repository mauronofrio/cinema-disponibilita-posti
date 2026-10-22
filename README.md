# Cinema: Disponibilità & Posti

App Android **non ufficiale** per chi vuole solo sapere due cose, in fretta: *cosa danno oggi* e *quanti posti sono ancora liberi*. Niente account, niente pagamenti, niente prenotazioni: solo programmazione e mappa posti, prese dagli stessi dati già pubblici sui siti ufficiali.

Nata per risolvere due fastidi delle app ufficiali: l'etichetta "oggi" che a volte resta bloccata su ieri dopo la mezzanotte, e i tempi di caricamento della mappa posti - lenti non perché l'endpoint dei posti sia lento, ma perché l'app/sito ufficiale avviano l'intero flusso di prenotazione (ordine, pagamento, concessioni) prima ancora di mostrarti i posti liberi. Questa app salta dritta al punto.

## Cosa fa

- Scegli il tuo cinema preferito da una lista ricercabile per nome, catena o città (o più di uno, e passa dall'uno all'altro dalle impostazioni)
- Vedi gli spettacoli divisi per giorno, con locandina e orari (tocca la locandina per aprirla a schermo intero e ingrandirla)
- Apri uno spettacolo e vedi subito la mappa posti: liberi, occupati, riservati, accessibilità - con legenda
- Un tasto "i" su ogni film apre trama (nella lingua dell'app) e trailer YouTube, presi da TMDb solo quando lo tocchi - mai richiesti in anticipo, e mai una seconda volta per lo stesso film
- Da lì puoi cambiare giorno o orario senza tornare indietro alla lista film
- Un tasto ti manda alla pagina ufficiale se vuoi comprare davvero il biglietto
- Ti avvisa in automatico quando è disponibile una versione più recente (l'app non passa da nessuno store), con un tasto per leggere le novità prima di scaricarla
- L'elenco dei cinema si aggiorna da solo (al massimo una volta al giorno, da questo repository): i nuovi cinema arrivano senza dover installare una nuova versione
- La programmazione già vista resta salvata sul telefono: passando da un cinema all'altro o riaprendo l'app non viene richiesta di nuovo ai siti dei cinema. Si riscarica solo tirando giù per aggiornare, oppure una volta dopo le 11 del giorno in questione se era stata scaricata prima (molte sale piccole sistemano la programmazione del giorno in mattinata). Le mappe posti invece sono sempre dal vivo

## Cinema supportati

<!-- cinema-counts:start -->
**292 cinema supportati** · The Space 35 · UCI 33 · 18tickets 146 · Webtic 56 · 2Tickets 22
<!-- cinema-counts:end -->

| Catena | Copertura |
|---|---|
| The Space Cinema | 35 sale in tutta Italia |
| UCI Cinemas | 33 sale in tutta Italia |
| Cinema indipendenti sulla piattaforma "18tickets.net" | RedCarpet Cinema (Monopoli), Multicinema Galleria (Bari), Anteo spazioCinema (Lombardia), Circuito Cinema (Bologna, Roma, Napoli, Firenze, Torino), Pop Up Cinema (Bologna), Multisala Impero (Varese), Multisala Massimo (Lecce), Cinemazero (Pordenone), Andromeda (Roma, Brindisi, Zumpano), Multisala Paolillo (Barletta), Multicinema Mangiatordi (Altamura), Pixel Cinema (Santeramo in Colle), Metropolis Multicine (Mola di Bari), Cinema Moderno e Ciak (Maglie), Spazio Alfieri e Flora (Firenze), Cosenza Cinema (Citrigno, Italia, Unical), Kinemax (Monfalcone), Cinecity (Lignano Sabbiadoro), Cine Teatro Eden (Termini Imerese), Cinema Golden (Marsala), altri cinema indipendenti nel Lazio (Roma, Rieti, Aprilia, Latina, Tarquinia, Frascati, Genzano, Velletri), in Veneto (Padova, Vicenza, Venezia, Verona), a Genova, Trento, Udine, Napoli, Bergamo, Palermo, L'Aquila, Avezzano, Spoltore, Silvi, Benevento, Afragola, Andria, Lecce (Db Arena) e in altre città sparse (Civitavecchia, Catanzaro, Praia a Mare, Olbia, Alessandria, Ovada, Pavia, Suzzara, Carpi, Savona, La Spezia, Lerici, Carrara, Capalbio, Paderno Dugnano, Concordia Sagittaria, San Daniele del Friuli, Romano di Lombardia, Calusco d'Adda, Taranto, Ancona, Fabriano, Sassari, Torino, Gavirate, Belluno, Mercogliano, Ladispoli, Gorizia, Milano) |
| Cinema indipendenti sulla piattaforma "2Tickets.it" | Cine Teatro Norba (Conversano), Multisala Vignola (Polignano a Mare), Cinema Teatro Orfeo (Taranto), Farnese ArtHouse Cinema e Cinema delle Provincie (Roma), Cinema Ariston (Trieste), Cinema Teatro Ariston (Gaeta), Multisala Grillo e Cinema Eden (Mazara del Vallo), Multisala Centrale (Volterra), Cinema Margherita (Acireale), Multisala King e Arena Adua (Catania), Cinema Moderno (Mascalucia), Multisala Badia Grande (Sciacca), Cineteatro San Timoteo (Casal Palocco), Teatro Busnelli (Dueville), Cinema Due Torri e Cineteatro Don Bosco (Potenza), Cinema Tartaro (Galatina), Teatro Bismantova (Castelnovo ne' Monti), Cinema Teatro Multisala Moderno (Anzio) |
| Notorious Cinemas, Giometti Cinema, Il Regno del Cinema, Cineplexx, Movie Planet, Madison Cinemas e altri (piattaforma "Webtic") | Notorious: 8 sale. Giometti: 11 sale in Marche/Toscana/Emilia-Romagna. Il Regno del Cinema: 6 sale a Brescia/Crema/Milano. Cineplexx: 2 sale in Alto Adige. Movie Planet: 3 sale (Parona, Borgo Vercelli, Vercelli). Madison Cinemas: 4 sale (Grottaferrata, Iglesias, Roma, Pianoro-Bologna). Altre sale indipendenti a Roma (Adriano, Atlantic, Europa, Savoy, Trevignano Romano), Viareggio (Centrale, Goldoni), Mantova (Cinecity, Mignon), Arese, Ascoli Piceno, La Spezia, Cefalù, Grosseto, e a Milano (Cinema Ducale, Arcobaleno Film Center, Orfeo Multisala, Plinius Multisala), Firenze, Pisa, Palermo (Marconi), più Nuovo Eden a Brescia |

Ognuna di queste catene parla un'API diversa (alcune un JSON pulito, altre solo HTML/SVG server-renderizzato) - vedi `PROJECT_NOTES.md` (locale, non versionato) per i dettagli del reverse engineering di ciascuna.

**Manca il tuo cinema?** Segnalalo con [questo form](https://forms.gle/ZvtR5KVo3nEwKaGP9).

## Com'è fatta

Flutter, nessun backend proprio: l'app chiama direttamente le API/i siti pubblici delle catene supportate.

- **Stato**: Riverpod (`flutter_riverpod`), cache in-memory con TTL brevi per le mappe posti. Persistenza locale (`shared_preferences`) solo per il cinema preferito, per l'ultimo elenco cinema scaricato, per la programmazione già vista (per cinema e giorno, regola delle 11 in `schedule_freshness.dart`, giorni passati cancellati all'avvio) e per la cache di trama/trailer (per titolo film, non per cinema - un film richiesto una volta non lo richiede più nemmeno da un altro cinema, pulita ogni 60 giorni)
- **Rete**: `dio`, un client per catena, più un client TMDb indipendente dalle catene per trama/trailer
- **Routing**: `go_router`
- **Un'astrazione, cinque implementazioni**: ogni catena implementa la stessa `ChainApi` (`getShowingDates`/`getFilmsForDay`/`getSeatMap`); schermate e provider non sanno mai con quale catena stanno parlando. Aggiungere una nuova catena (o un nuovo cinema indipendente sulla stessa piattaforma) è una nuova classe più una riga nel registro, senza toccare l'interfaccia utente

## Sviluppo

```bash
flutter pub get
flutter test
flutter run          # debug, su emulatore o device connesso
flutter build apk --release --dart-define=TMDB_READ_ACCESS_TOKEN=...  # trama/trailer film (facoltativo, senza la app funziona lo stesso)
```

Prima di pubblicare un nuovo cinema nell'elenco, si verifica che funzioni davvero con il codice dell'app, su dati reali (programmazione, mappa posti e link di acquisto). Il controllo fa richieste di rete, quindi non gira con `flutter test`:

```bash
flutter test --run-skipped --tags live test/live --dart-define=VERIFY_CHAIN=eighteenTickets
```

Altri `--dart-define` opzionali: `VERIFY_FILE` (default `assets/cinemas.json`), `VERIFY_IDS` (elenco di `cinemaId` separati da virgola), `VERIFY_DELAY_MS` (pausa tra un cinema e l'altro, default 4000), `VERIFY_REPORT`. Il rapporto finisce in `build/navigability_report.json`.

### Rilascio

- Fare il push di `master` (con l'`assets/cinemas.json` definitivo) **prima** di pubblicare l'APK o di provare una build release su un dispositivo: l'app scarica l'elenco dei cinema proprio da quel file.
- Non rinominare mai il branch `master` e non spostare `assets/cinemas.json`: le app già installate leggono quell'URL esatto e non possono essere aggiornate.
- Per nascondere un cinema, aggiungere `"minAppVersion"` alla sua voce invece di cancellarla: una voce cancellata dall'elenco remoto torna comunque visibile nelle app che la includono già.

## Sostieni il progetto

L'app è gratuita e senza pubblicità. Se ti è utile, puoi offrirmi un caffè su [PayPal](https://www.paypal.me/MauronofrioTool) (c'è anche un tasto nelle impostazioni dell'app).

## Disclaimer

App non ufficiale, senza alcun legame con The Space Cinema, Vue International, UCI Cinemas o con nessuno dei cinema indipendenti elencati sopra. Non gestisce account, pagamenti, biglietti o prenotazioni: mostra soltanto programmazione e disponibilità posti, dati già pubblicamente visibili sui siti ufficiali.
