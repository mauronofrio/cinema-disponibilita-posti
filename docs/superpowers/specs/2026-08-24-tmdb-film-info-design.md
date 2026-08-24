# Trama e trailer via TMDb

## Obiettivo

Dare accesso a una descrizione del film (trama, nella lingua dell'app) e a un
link al trailer su YouTube, richiamabili on-demand da un tasto/icona sia
sulla lista spettacoli (`FilmCard`) sia sulla schermata mappa posti
(`SeatMapScreen`). Nessuna chiamata esterna finché l'utente non tocca
esplicitamente quel tasto. Una volta scaricati i dati di un film, non vanno
più richiesti né per lo stesso film su un altro cinema, né in un momento
successivo della stessa sessione, né - passato meno di 60 giorni - in una
sessione futura dell'app.

Fuori scope per questa versione: link/rating IMDb, player video integrato,
pulizia automatica oltre al controllo dei 60 giorni all'avvio.

## Fonte dati: TMDb

The Movie Database (`api.themoviedb.org/3`), autenticazione via header
`Authorization: Bearer <TMDB_READ_ACCESS_TOKEN>` (v4, JWT) - non il vecchio
schema `?api_key=`. Due chiamate quando serve un film mai visto prima:

1. `GET /search/movie?query={titolo}&language={it-IT|en-US}` - il primo
   risultato più rilevante; `overview` è già nella lingua richiesta.
2. `GET /movie/{id}/videos?language={it-IT|en-US}` - filtrato a
   `site == "YouTube" && type == "Trailer"`, preferendo `official == true`
   se presente più di un trailer; l'URL finale è
   `https://www.youtube.com/watch?v={key}`.

La lingua è quella effettiva dell'app (`AppLocalizations`/`effectiveLocaleProvider`
esistente), mappata `it` → `it-IT`, `en` → `en-US`.

Se `/search/movie` non restituisce risultati, o una delle due chiamate
fallisce (rete/HTTP), il film è trattato come "non disponibile" - vedi
sezione Errori.

## Titolo di ricerca

Il titolo passato a TMDb è `film.title` con l'unica ripulitura del suffisso
che l'app stessa aggiunge per disambiguare i duplicati 18tickets (vedi
`_disambiguateDuplicateTitles` in `eighteen_tickets_film_parser.dart`, pattern
`" · {label}"`) - nessun'altra normalizzazione (maiuscole, anni tra
parentesi, ecc.) in questa prima versione.

## Componenti

- **`lib/core/network/tmdb_api_client.dart`** - `TmdbApiClient`, stesso
  pattern dio + `throwFriendlyDioError` degli altri client (`myuci_api_client.dart`
  ecc.). Due metodi: `searchMovie(String title, String language)` e
  `getTrailerKey(int tmdbId, String language)`, entrambi ritornano il body
  raw (JSON stringa) - nessun parsing qui.
- **`lib/core/chains/tmdb/tmdb_film_info_parser.dart`** - funzioni pure,
  testabili con fixture JSON statiche, sullo stile dei parser di
  webtic/eighteenTickets:
  - `parseTmdbSearchResult(String json) -> ({int id, String overview})?`
    (`null` se `results` è vuoto)
  - `parseTmdbTrailerKey(String json) -> String?` (`null` se nessun video
    YouTube di tipo Trailer)
- **`lib/core/storage/film_info_store.dart`** - `FilmInfoStore`, stesso
  pattern di `FavoriteCinemaStore` (shared_preferences). Un'unica chiave
  `film_info_cache` che contiene una mappa JSON `{titolo: {overview,
  trailerUrl, fetchedAt}}` (`trailerUrl` opzionale, `fetchedAt` ISO8601 via
  `Clock`, mai `DateTime.now()` diretto - vedi `core/date/clock.dart`).
  Metodi: `read(String title) -> FilmInfo?`, `write(String title, FilmInfo
  info)`, `purgeOlderThan(DateTime cutoff)`.
- **`lib/features/film_info/film_info_provider.dart`** - `FutureProvider.family<FilmInfo,
  String>` keyed sul titolo pulito: prima legge da `FilmInfoStore`, se
  assente fa le due chiamate TMDb, poi scrive in `FilmInfoStore` e ritorna.
  Lancia un'eccezione dedicata (es. `FilmInfoUnavailableException`) quando
  TMDb non trova nulla, così la UI la distingue da un errore di rete se
  utile in futuro (per ora entrambe mostrano lo stesso messaggio).
- **`lib/features/film_info/film_info_sheet.dart`** - il bottom sheet
  (`showModalBottomSheet`): locandina/titolo/durata mostrati subito (già
  noti, nessuna chiamata), poi `Consumer` che guarda il provider - loading
  spinner, poi trama + tasto trailer (se presente), oppure il messaggio
  "Descrizione non disponibile" in caso di errore o nessun trailer/trama
  trovati. Il tasto trailer usa `launchUrl(..., mode:
  LaunchMode.externalApplication)`, stesso schema di
  `_confirmAndOpenDirections`/`BuyTicketsButton`.
- **Pulizia all'avvio**: in `app.dart`, accanto al pattern già esistente di
  `_UpdateCheckGate` (un side-effect one-shot al primo frame), una chiamata
  a `FilmInfoStore.purgeOlderThan(clock.now().subtract(Duration(days: 60)))`.

## Punti di accesso UI

- `FilmCard`: icona (`Icons.info_outline`) accanto al titolo, apre il
  bottom sheet passando `film`.
- `SeatMapScreen`: stessa icona nell'AppBar accanto al titolo del film già
  mostrato lì.

## Chiave API

Letta con `const String.fromEnvironment('TMDB_READ_ACCESS_TOKEN')`, passata
a `flutter build`/`flutter run` con `--dart-define=TMDB_READ_ACCESS_TOKEN=...`
- mai committata. Se la costante è vuota a runtime, l'icona resta comunque
visibile (evita una chiamata di verifica preventiva per ogni film in lista,
in contrasto con "solo se necessario") ma il tap mostra subito il messaggio
"Descrizione non disponibile" senza tentare la chiamata di rete.

## Errori

Un solo stato d'errore visibile in UI ("Descrizione non disponibile"),
raggiunto da: chiave mancante, nessun risultato di ricerca, richiesta di
rete fallita. Il trailer è facoltativo anche a successo: se la trama viene
trovata ma nessun trailer YouTube esiste, il pannello mostra solo la trama,
senza il tasto.

## Test

- `parseTmdbSearchResult`/`parseTmdbTrailerKey`: fixture JSON statiche
  (risultato vuoto, risultato singolo, più trailer con uno `official`).
- `FilmInfoStore`: `purgeOlderThan` con voci finte a età diverse (stesso
  stile dei test di `TtlCache`/`Clock` iniettato, non `DateTime.now()`
  diretto).
- Titolo di ricerca: la funzione che toglie il suffisso `" · {label}"`,
  se estratta a parte, testata sui casi con e senza suffisso.
- Nessun test per `TmdbApiClient` stesso (nessuna infrastruttura di mock
  HTTP nel progetto, coerente con gli altri client) né per i widget (nessun
  widget test esiste già per `film_card.dart`/`seat_map_screen.dart`).
