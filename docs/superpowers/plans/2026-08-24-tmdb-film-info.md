# Trama e trailer via TMDb — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aggiungere un tasto "i" su `FilmCard` e su `SeatMapScreen` che apre un bottom sheet con trama (nella lingua dell'app) e link al trailer YouTube di un film, dati presi da TMDb solo al momento del tap e mai richiesti di nuovo per lo stesso film (cache persistente, pulita ogni 60 giorni all'avvio).

**Architecture:** Nuovo modulo indipendente dalle 4 `ChainApi` esistenti (questo è un dato per-film, non per-catena): un client HTTP sottile (`TmdbApiClient`), un parser puro testabile (`tmdb_film_info_parser.dart`), uno store `shared_preferences` (`FilmInfoStore`, stesso pattern di `FavoriteCinemaStore`), un `FutureProvider.family` che li lega, e un bottom sheet condiviso richiamato da entrambi i punti di accesso.

**Tech Stack:** Flutter/Dart, `dio` (HTTP), `flutter_riverpod` (state), `shared_preferences` (persistenza) — tutte già dipendenze del progetto, nessun nuovo package.

**Spec:** `docs/superpowers/specs/2026-08-24-tmdb-film-info-design.md`

## Global Constraints

- Nessuna chiamata di rete finché l'utente non tocca esplicitamente il tasto "i" (niente pre-fetch, niente verifica preventiva di disponibilità).
- Chiave TMDb letta con `const String.fromEnvironment('TMDB_READ_ACCESS_TOKEN')`, mai committata in chiaro; passata a `flutter build`/`flutter run` con `--dart-define=TMDB_READ_ACCESS_TOKEN=...`.
- Autenticazione TMDb: header `Authorization: Bearer <token>` (v4), non `?api_key=`.
- Lingua: `it` → `it-IT`, `en` → `en-US`, presa da `effectiveLocaleProvider` (`lib/core/localization/locale_provider.dart`).
- Cache per titolo film, persistente su `shared_preferences`, nessuna scadenza salvo la pulizia dei 60 giorni all'avvio.
- Un solo stato d'errore in UI ("Descrizione non disponibile"), per: chiave mancante, nessun risultato TMDb, richiesta di rete fallita.
- Il trailer è facoltativo anche a successo: se la trama c'è ma nessun trailer YouTube, il pannello mostra solo la trama.
- Il tasto trailer apre YouTube esternamente (`url_launcher`, `LaunchMode.externalApplication`), nessun player integrato.
- Ogni `DateTime` "adesso" passa da `ref.read(clockProvider).now()` (`lib/core/date/clock.dart`), mai `DateTime.now()` diretto.

---

## File Structure

- **Create** `lib/core/chains/tmdb/tmdb_film_info_parser.dart` — funzioni pure: `cleanTitleForSearch`, `parseTmdbSearchResult`, `parseTmdbTrailerKey`.
- **Create** `lib/core/storage/film_info_store.dart` — `FilmInfo` (modello + JSON), `FilmInfoStore` (shared_preferences), `filmInfoStoreProvider`.
- **Create** `lib/core/network/tmdb_api_client.dart` — `TmdbApiClient`, `tmdbApiClientProvider` (stesso pattern di `eighteen_tickets_api_client.dart`: client + provider nello stesso file, Dio costruito inline).
- **Create** `lib/features/film_info/film_info_provider.dart` — `FilmInfoUnavailableException`, `filmInfoProvider` (`FutureProvider.family<FilmInfo, String>`).
- **Create** `lib/features/film_info/film_info_sheet.dart` — `FilmInfoArgs`, `showFilmInfoSheet`, `FilmInfoSheet`.
- **Modify** `lib/core/localization/app_localizations.dart` — 3 nuove stringhe (`filmInfoTooltip`, `filmInfoUnavailable`, `watchTrailer`).
- **Modify** `lib/features/seat_map/seat_map_provider.dart` — `SeatMapArgs` guadagna `posterImageSrc`/`runningTime`.
- **Modify** `lib/features/showtimes/widgets/film_card.dart` — icona "i" accanto al titolo; passa i due nuovi campi quando costruisce `SeatMapArgs`.
- **Modify** `lib/features/seat_map/seat_map_screen.dart` — icona "i" nell'AppBar.
- **Modify** `lib/app.dart` — pulizia cache all'avvio (60 giorni).
- **Modify** `README.md` — nota sul `--dart-define` richiesto in "Sviluppo".
- **Create** `test/fixtures/tmdb_search_movie_sample.json`, `test/fixtures/tmdb_search_movie_empty_sample.json`, `test/fixtures/tmdb_movie_videos_sample.json`, `test/fixtures/tmdb_movie_videos_no_youtube_sample.json`.
- **Create** `test/core/tmdb_film_info_parser_test.dart`, `test/core/film_info_store_test.dart`.

---

### Task 1: Parser puro TMDb (titolo di ricerca, risultato ricerca, trailer)

**Files:**
- Create: `lib/core/chains/tmdb/tmdb_film_info_parser.dart`
- Create: `test/fixtures/tmdb_search_movie_sample.json`
- Create: `test/fixtures/tmdb_search_movie_empty_sample.json`
- Create: `test/fixtures/tmdb_movie_videos_sample.json`
- Create: `test/fixtures/tmdb_movie_videos_no_youtube_sample.json`
- Test: `test/core/tmdb_film_info_parser_test.dart`

**Interfaces:**
- Produces: `String cleanTitleForSearch(String title)`, `class TmdbSearchResult { final int id; final String overview; }`, `TmdbSearchResult? parseTmdbSearchResult(String responseBody)`, `String? parseTmdbTrailerKey(String responseBody)`.

- [ ] **Step 1: Crea le fixture JSON**

`test/fixtures/tmdb_search_movie_sample.json`:
```json
{
  "page": 1,
  "results": [
    {
      "id": 1241436,
      "title": "Oceania",
      "overview": "Nell'adattamento live-action Disney dell'acclamata avventura animata, Vaiana risponde al richiamo dell'oceano.",
      "release_date": "2026-08-19"
    }
  ],
  "total_pages": 1,
  "total_results": 1
}
```

`test/fixtures/tmdb_search_movie_empty_sample.json`:
```json
{
  "page": 1,
  "results": [],
  "total_pages": 1,
  "total_results": 0
}
```

`test/fixtures/tmdb_movie_videos_sample.json`:
```json
{
  "id": 1241436,
  "results": [
    {
      "key": "def456uvw",
      "site": "YouTube",
      "type": "Teaser",
      "official": false,
      "name": "Teaser"
    },
    {
      "key": "abc123xyz",
      "site": "YouTube",
      "type": "Trailer",
      "official": true,
      "name": "Trailer Ufficiale"
    },
    {
      "key": "ghi789rst",
      "site": "Vimeo",
      "type": "Trailer",
      "official": true,
      "name": "Trailer (Vimeo mirror)"
    }
  ]
}
```

`test/fixtures/tmdb_movie_videos_no_youtube_sample.json`:
```json
{
  "id": 1241436,
  "results": [
    {
      "key": "ghi789rst",
      "site": "Vimeo",
      "type": "Trailer",
      "official": true,
      "name": "Trailer (Vimeo mirror)"
    }
  ]
}
```

- [ ] **Step 2: Scrivi i test (falliranno: il file del parser non esiste ancora)**

`test/core/tmdb_film_info_parser_test.dart`:
```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/chains/tmdb/tmdb_film_info_parser.dart';

void main() {
  group('cleanTitleForSearch', () {
    test('a plain title with no disambiguation suffix is unchanged', () {
      expect(cleanTitleForSearch('OCEANIA (LIVE ACTION 2026)'),
          'OCEANIA (LIVE ACTION 2026)');
    });

    test(
      'this is the actual regression case: the " · {label}" suffix this app '
      'itself appends to disambiguate duplicate 18tickets titles (see '
      'eighteen_tickets_film_parser.dart) is stripped before searching, '
      'since TMDb has never heard of "OCEANIA (MOANA) · Sing-Along"',
      () {
        expect(
          cleanTitleForSearch('OCEANIA (MOANA) · 🎤 Sing-Along'),
          'OCEANIA (MOANA)',
        );
      },
    );
  });

  group('parseTmdbSearchResult', () {
    test('reads id and overview off the first result', () {
      final body = File(
        'test/fixtures/tmdb_search_movie_sample.json',
      ).readAsStringSync();
      final result = parseTmdbSearchResult(body);
      expect(result, isNotNull);
      expect(result!.id, 1241436);
      expect(result.overview, contains('Vaiana'));
    });

    test('an empty results list returns null, not a crash', () {
      final body = File(
        'test/fixtures/tmdb_search_movie_empty_sample.json',
      ).readAsStringSync();
      expect(parseTmdbSearchResult(body), isNull);
    });
  });

  group('parseTmdbTrailerKey', () {
    test(
      'prefers the official YouTube Trailer over a non-official Teaser and '
      'over a Trailer hosted on a different site',
      () {
        final body = File(
          'test/fixtures/tmdb_movie_videos_sample.json',
        ).readAsStringSync();
        expect(parseTmdbTrailerKey(body), 'abc123xyz');
      },
    );

    test('no YouTube video at all returns null, not a crash', () {
      final body = File(
        'test/fixtures/tmdb_movie_videos_no_youtube_sample.json',
      ).readAsStringSync();
      expect(parseTmdbTrailerKey(body), isNull);
    });
  });
}
```

- [ ] **Step 3: Esegui i test per verificare che falliscano**

Run: `flutter test test/core/tmdb_film_info_parser_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:thespace_companion/core/chains/tmdb/tmdb_film_info_parser.dart'`.

- [ ] **Step 4: Implementa il parser**

`lib/core/chains/tmdb/tmdb_film_info_parser.dart`:
```dart
import 'dart:convert';

/// TMDb has never heard of the " · {label}" suffix this app itself appends
/// to disambiguate duplicate 18tickets titles (see
/// eighteen_tickets_film_parser.dart's `_disambiguateDuplicateTitles`) - it
/// isn't part of the real film title, so it's stripped before searching.
String cleanTitleForSearch(String title) {
  final separatorIndex = title.indexOf(' · ');
  return separatorIndex == -1 ? title : title.substring(0, separatorIndex);
}

/// The one TMDb search result this app actually needs: enough to fetch the
/// trailer separately ([id]) and to show a plot right away ([overview]).
class TmdbSearchResult {
  const TmdbSearchResult({required this.id, required this.overview});

  final int id;
  final String overview;
}

/// The first (most relevant, per TMDb's own ranking) search result, or
/// `null` when there are no results or the top one has no overview at all -
/// treated as "no usable match" rather than showing an empty description.
TmdbSearchResult? parseTmdbSearchResult(String responseBody) {
  final decoded = json.decode(responseBody) as Map<String, dynamic>;
  final results = decoded['results'] as List<dynamic>? ?? const [];
  if (results.isEmpty) return null;
  final first = results.first as Map<String, dynamic>;
  final overview = (first['overview'] as String?) ?? '';
  if (overview.isEmpty) return null;
  return TmdbSearchResult(id: first['id'] as int, overview: overview);
}

/// The YouTube trailer key to build `https://www.youtube.com/watch?v={key}`
/// from, or `null` if this film has no YouTube video of type Trailer at
/// all. Prefers one flagged `official` when more than one exists.
String? parseTmdbTrailerKey(String responseBody) {
  final decoded = json.decode(responseBody) as Map<String, dynamic>;
  final videos = (decoded['results'] as List<dynamic>? ?? const [])
      .cast<Map<String, dynamic>>()
      .where((v) => v['site'] == 'YouTube' && v['type'] == 'Trailer')
      .toList();
  if (videos.isEmpty) return null;
  final chosen = videos.firstWhere(
    (v) => v['official'] == true,
    orElse: () => videos.first,
  );
  return chosen['key'] as String?;
}
```

- [ ] **Step 5: Esegui i test per verificare che passino**

Run: `flutter test test/core/tmdb_film_info_parser_test.dart`
Expected: PASS (6 test).

- [ ] **Step 6: Commit**

```bash
git add lib/core/chains/tmdb/tmdb_film_info_parser.dart test/core/tmdb_film_info_parser_test.dart test/fixtures/tmdb_search_movie_sample.json test/fixtures/tmdb_search_movie_empty_sample.json test/fixtures/tmdb_movie_videos_sample.json test/fixtures/tmdb_movie_videos_no_youtube_sample.json
git commit -m "Aggiungi il parser puro per le risposte TMDb (ricerca film, trailer)"
```

---

### Task 2: `FilmInfo` e `FilmInfoStore` (cache persistente su shared_preferences)

**Files:**
- Create: `lib/core/storage/film_info_store.dart`
- Test: `test/core/film_info_store_test.dart`

**Interfaces:**
- Consumes: nulla dai task precedenti.
- Produces: `class FilmInfo { final String overview; final String? trailerUrl; final DateTime fetchedAt; }` con `toJson()`/`FilmInfo.fromJson`; `class FilmInfoStore { Future<FilmInfo?> read(String title); Future<void> write(String title, FilmInfo info); Future<void> purgeOlderThan(DateTime cutoff); }`; `final filmInfoStoreProvider = Provider<FilmInfoStore>(...)`.

- [ ] **Step 1: Scrivi i test (falliranno: il file non esiste ancora)**

`test/core/film_info_store_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thespace_companion/core/storage/film_info_store.dart';

void main() {
  setUp(() {
    // Fresh, empty prefs for every test - same in-memory test backend
    // FavoriteCinemaStore's own tests use.
    SharedPreferences.setMockInitialValues({});
  });

  group('FilmInfoStore', () {
    test('read returns null for a title never written', () async {
      final store = FilmInfoStore();
      expect(await store.read('Never Seen'), isNull);
    });

    test('write then read round-trips overview, trailerUrl and fetchedAt', () async {
      final store = FilmInfoStore();
      final info = FilmInfo(
        overview: 'Trama di prova.',
        trailerUrl: 'https://www.youtube.com/watch?v=abc123xyz',
        fetchedAt: DateTime(2026, 8, 24, 12),
      );

      await store.write('Oceania', info);
      final read = await store.read('Oceania');

      expect(read, isNotNull);
      expect(read!.overview, 'Trama di prova.');
      expect(read.trailerUrl, 'https://www.youtube.com/watch?v=abc123xyz');
      expect(read.fetchedAt, DateTime(2026, 8, 24, 12));
    });

    test('trailerUrl round-trips as null when a film has no trailer', () async {
      final store = FilmInfoStore();
      final info = FilmInfo(
        overview: 'Trama senza trailer.',
        trailerUrl: null,
        fetchedAt: DateTime(2026, 8, 24, 12),
      );

      await store.write('Un Film Di Nicchia', info);

      expect((await store.read('Un Film Di Nicchia'))!.trailerUrl, isNull);
    });

    test(
      'this is the actual feature: the same title written once is read '
      'back unchanged regardless of which cinema/chain is asking - the '
      'store is keyed only by title, never by cinema',
      () async {
        final store = FilmInfoStore();
        final info = FilmInfo(
          overview: 'Trama condivisa tra cinema.',
          trailerUrl: null,
          fetchedAt: DateTime(2026, 8, 24, 12),
        );

        await store.write('Coyote vs Acme', info);

        // Same title, read as if from a completely different cinema/chain -
        // no cinema/chain parameter exists on read() at all.
        expect((await store.read('Coyote vs Acme'))!.overview, info.overview);
      },
    );

    test('writing a second film does not disturb the first', () async {
      final store = FilmInfoStore();
      await store.write(
        'Film A',
        FilmInfo(overview: 'A', trailerUrl: null, fetchedAt: DateTime(2026, 8, 1)),
      );
      await store.write(
        'Film B',
        FilmInfo(overview: 'B', trailerUrl: null, fetchedAt: DateTime(2026, 8, 2)),
      );

      expect((await store.read('Film A'))!.overview, 'A');
      expect((await store.read('Film B'))!.overview, 'B');
    });

    test(
      'purgeOlderThan removes only entries fetched before the cutoff',
      () async {
        final store = FilmInfoStore();
        await store.write(
          'Vecchio',
          FilmInfo(overview: 'x', trailerUrl: null, fetchedAt: DateTime(2026, 6, 1)),
        );
        await store.write(
          'Recente',
          FilmInfo(overview: 'y', trailerUrl: null, fetchedAt: DateTime(2026, 8, 20)),
        );

        await store.purgeOlderThan(DateTime(2026, 8, 1));

        expect(await store.read('Vecchio'), isNull);
        expect(await store.read('Recente'), isNotNull);
      },
    );

    test('purgeOlderThan on an empty cache is a no-op, not a crash', () async {
      final store = FilmInfoStore();
      await store.purgeOlderThan(DateTime(2026, 8, 1));
      expect(await store.read('Qualsiasi'), isNull);
    });
  });
}
```

- [ ] **Step 2: Esegui i test per verificare che falliscano**

Run: `flutter test test/core/film_info_store_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:thespace_companion/core/storage/film_info_store.dart'`.

- [ ] **Step 3: Implementa `FilmInfo` e `FilmInfoStore`**

`lib/core/storage/film_info_store.dart`:
```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One film's TMDb data, cached exactly as shown in the UI - no re-fetch
/// logic lives here, this is pure storage.
class FilmInfo {
  const FilmInfo({
    required this.overview,
    required this.trailerUrl,
    required this.fetchedAt,
  });

  final String overview;
  final String? trailerUrl;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => {
    'overview': overview,
    'trailerUrl': trailerUrl,
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  factory FilmInfo.fromJson(Map<String, dynamic> json) => FilmInfo(
    overview: json['overview'] as String,
    trailerUrl: json['trailerUrl'] as String?,
    fetchedAt: DateTime.parse(json['fetchedAt'] as String),
  );
}

/// Persists TMDb film info keyed by film *title* only (never by cinema or
/// chain) - the whole point is that asking once for a film shown at one
/// cinema must never trigger a second TMDb call for the same film shown at
/// another cinema, or reopened later. One shared_preferences entry holding
/// a JSON map, same "small enough that a single key is simpler than one key
/// per entry" reasoning as [FavoriteCinemaStore]'s own two keys - realistic
/// scale here is at most a few hundred films ever, a few KB total.
class FilmInfoStore {
  static const _prefsKey = 'film_info_cache';

  Future<Map<String, dynamic>> _readAll(SharedPreferences prefs) async {
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {};
    return json.decode(raw) as Map<String, dynamic>;
  }

  Future<FilmInfo?> read(String title) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll(prefs);
    final entry = all[title] as Map<String, dynamic>?;
    if (entry == null) return null;
    return FilmInfo.fromJson(entry);
  }

  Future<void> write(String title, FilmInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll(prefs);
    all[title] = info.toJson();
    await prefs.setString(_prefsKey, json.encode(all));
  }

  /// Called once at app startup (see app.dart) - not a TTL on read, just
  /// housekeeping so the cache doesn't grow forever across months of use.
  Future<void> purgeOlderThan(DateTime cutoff) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll(prefs);
    all.removeWhere((_, value) {
      final fetchedAt = DateTime.parse(
        (value as Map<String, dynamic>)['fetchedAt'] as String,
      );
      return fetchedAt.isBefore(cutoff);
    });
    await prefs.setString(_prefsKey, json.encode(all));
  }
}

final filmInfoStoreProvider = Provider<FilmInfoStore>((ref) => FilmInfoStore());
```

- [ ] **Step 4: Esegui i test per verificare che passino**

Run: `flutter test test/core/film_info_store_test.dart`
Expected: PASS (7 test).

- [ ] **Step 5: Commit**

```bash
git add lib/core/storage/film_info_store.dart test/core/film_info_store_test.dart
git commit -m "Aggiungi FilmInfoStore: cache persistente TMDb per titolo film"
```

---

### Task 3: `TmdbApiClient`

**Files:**
- Create: `lib/core/network/tmdb_api_client.dart`

**Interfaces:**
- Consumes: nulla dai task precedenti (nessun test automatico per questo file - stesso motivo già vero per ogni altro client HTTP del progetto: nessuna infrastruttura di mock HTTP).
- Produces: `class TmdbApiClient { Future<String> searchMovie(String title, String language); Future<String> getVideos(int tmdbId, String language); }`; `final tmdbApiClientProvider = Provider<TmdbApiClient>(...)`.

- [ ] **Step 1: Implementa il client**

`lib/core/network/tmdb_api_client.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dio_error.dart';

const _tmdbBaseUrl = 'https://api.themoviedb.org/3';

/// Read with `--dart-define=TMDB_READ_ACCESS_TOKEN=...` at build/run time -
/// never committed. Empty when the app was built without it; callers (see
/// film_info_provider.dart) check for that *before* ever constructing this
/// client, so an empty token here never actually reaches a real request.
const tmdbReadAccessToken = String.fromEnvironment('TMDB_READ_ACCESS_TOKEN');

/// Typed client for TMDb's read-only search/videos endpoints. Same
/// "client returns raw JSON text, a separate pure function parses it" split
/// as every other chain client (see tmdb_film_info_parser.dart).
class TmdbApiClient {
  TmdbApiClient(this._dio);

  final Dio _dio;

  Future<String> searchMovie(String title, String language) async {
    try {
      final response = await _dio.get<String>(
        '/search/movie',
        queryParameters: {'query': title, 'language': language},
        options: Options(responseType: ResponseType.plain),
      );
      return response.data!;
    } on DioException catch (e) {
      throwFriendlyDioError(e);
    }
  }

  Future<String> getVideos(int tmdbId, String language) async {
    try {
      final response = await _dio.get<String>(
        '/movie/$tmdbId/videos',
        queryParameters: {'language': language},
        options: Options(responseType: ResponseType.plain),
      );
      return response.data!;
    } on DioException catch (e) {
      throwFriendlyDioError(e);
    }
  }
}

final tmdbApiClientProvider = Provider<TmdbApiClient>((ref) {
  return TmdbApiClient(
    Dio(
      BaseOptions(
        baseUrl: _tmdbBaseUrl,
        headers: {'Authorization': 'Bearer $tmdbReadAccessToken'},
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    ),
  );
});
```

- [ ] **Step 2: Verifica che il progetto compili**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/network/tmdb_api_client.dart
git commit -m "Aggiungi TmdbApiClient"
```

---

### Task 4: `filmInfoProvider` e stringhe di localizzazione

**Files:**
- Create: `lib/features/film_info/film_info_provider.dart`
- Modify: `lib/core/localization/app_localizations.dart`

**Interfaces:**
- Consumes: `cleanTitleForSearch`, `parseTmdbSearchResult`, `parseTmdbTrailerKey` (Task 1); `FilmInfo`, `filmInfoStoreProvider` (Task 2); `tmdbApiClientProvider`, `tmdbReadAccessToken` (Task 3); `effectiveLocaleProvider` (`lib/core/localization/locale_provider.dart`, esistente); `clockProvider` (`lib/core/date/clock.dart`, esistente).
- Produces: `class FilmInfoUnavailableException implements Exception {}`; `final filmInfoProvider = FutureProvider.family<FilmInfo, String>(...)` (keyed sul titolo *grezzo*, non ripulito - la pulizia avviene dentro il provider così sia la cache sia la ricerca usano lo stesso titolo pulito).

- [ ] **Step 1: Implementa il provider**

`lib/features/film_info/film_info_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chains/tmdb/tmdb_film_info_parser.dart';
import '../../core/date/clock.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/network/tmdb_api_client.dart';
import '../../core/storage/film_info_store.dart';

/// Thrown for every "nothing to show" outcome - missing API key, no TMDb
/// match, or a failed request. The UI (film_info_sheet.dart) shows the same
/// single "not available" message for all three, per the design spec.
class FilmInfoUnavailableException implements Exception {}

/// Looks up a film's plot/trailer, in this order: the persistent cache
/// (film_info_store.dart, keyed by the *cleaned* title, shared across every
/// cinema/chain that shows this same film) first, then TMDb only if it
/// wasn't already there. Never called just by building this provider - only
/// by a widget actually watching/reading it, which only happens once the
/// user taps the info button (see film_info_sheet.dart).
final filmInfoProvider = FutureProvider.family<FilmInfo, String>((
  ref,
  rawTitle,
) async {
  final title = cleanTitleForSearch(rawTitle);
  final store = ref.watch(filmInfoStoreProvider);

  final cached = await store.read(title);
  if (cached != null) return cached;

  if (tmdbReadAccessToken.isEmpty) throw FilmInfoUnavailableException();

  final locale = ref.watch(effectiveLocaleProvider);
  final language = locale.languageCode == 'it' ? 'it-IT' : 'en-US';
  final client = ref.watch(tmdbApiClientProvider);

  final searchBody = await client.searchMovie(title, language);
  final searchResult = parseTmdbSearchResult(searchBody);
  if (searchResult == null) throw FilmInfoUnavailableException();

  // The trailer is optional even on a successful match (see the design
  // spec) - a video-fetch failure or "no YouTube trailer" still leaves the
  // overview worth showing, so this is deliberately not inside the same
  // try/catch scope as the search call above.
  String? trailerUrl;
  try {
    final videosBody = await client.getVideos(searchResult.id, language);
    final key = parseTmdbTrailerKey(videosBody);
    if (key != null) trailerUrl = 'https://www.youtube.com/watch?v=$key';
  } catch (_) {
    trailerUrl = null;
  }

  final info = FilmInfo(
    overview: searchResult.overview,
    trailerUrl: trailerUrl,
    fetchedAt: ref.read(clockProvider).now(),
  );
  await store.write(title, info);
  return info;
});
```

- [ ] **Step 2: Aggiungi le stringhe di localizzazione**

In `lib/core/localization/app_localizations.dart`, dentro `_strings` (subito dopo la voce `'sourceCode'`):
```dart
    'filmInfoTooltip': {
      'en': 'Description and trailer',
      'it': 'Descrizione e trailer',
    },
    'filmInfoUnavailable': {
      'en': 'Description not available.',
      'it': 'Descrizione non disponibile.',
    },
    'watchTrailer': {'en': 'Watch trailer', 'it': 'Guarda il trailer'},
```

E, subito dopo il getter `sourceCode`:
```dart
  String get filmInfoTooltip => _t('filmInfoTooltip');
  String get filmInfoUnavailable => _t('filmInfoUnavailable');
  String get watchTrailer => _t('watchTrailer');
```

- [ ] **Step 3: Verifica che il progetto compili**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/film_info/film_info_provider.dart lib/core/localization/app_localizations.dart
git commit -m "Aggiungi filmInfoProvider e le stringhe di localizzazione"
```

---

### Task 5: Bottom sheet e integrazione in `FilmCard`

**Files:**
- Create: `lib/features/film_info/film_info_sheet.dart`
- Modify: `lib/features/showtimes/widgets/film_card.dart`

**Interfaces:**
- Consumes: `filmInfoProvider`, `FilmInfoUnavailableException` (Task 4); `FilmInfo` (Task 2); `AppLocalizations`, `AppTheme`, `AppColors` (esistenti).
- Produces: `class FilmInfoArgs { final String title; final String? posterImageSrc; final int? runningTime; }`; `Future<void> showFilmInfoSheet(BuildContext context, FilmInfoArgs args)`.

- [ ] **Step 1: Implementa il bottom sheet**

`lib/features/film_info/film_info_sheet.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import 'film_info_provider.dart';

/// Just enough to show the header immediately (poster/title/runtime are
/// already known to the caller, no fetch needed for those) while
/// filmInfoProvider resolves the rest.
class FilmInfoArgs {
  const FilmInfoArgs({
    required this.title,
    required this.posterImageSrc,
    required this.runningTime,
  });

  final String title;
  final String? posterImageSrc;
  final int? runningTime;
}

Future<void> showFilmInfoSheet(BuildContext context, FilmInfoArgs args) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => FilmInfoSheet(args: args),
  );
}

class FilmInfoSheet extends ConsumerWidget {
  const FilmInfoSheet({super.key, required this.args});

  final FilmInfoArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    // Watching this here is what actually triggers the fetch - nothing
    // calls filmInfoProvider before this sheet is opened.
    final infoAsync = ref.watch(filmInfoProvider(args.title));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: args.posterImageSrc == null
                      ? Container(
                          width: 120,
                          height: 180,
                          color: AppColors.surfaceElevated,
                        )
                      : Image.network(
                          args.posterImageSrc!,
                          width: 120,
                          height: 180,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 120,
                            height: 180,
                            color: AppColors.surfaceElevated,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                args.title,
                style: AppTheme.display(context).copyWith(fontSize: 22),
              ),
              if (args.runningTime != null) ...[
                const SizedBox(height: 2),
                Text(
                  '${args.runningTime} min',
                  style: AppTheme.body(
                    context,
                  ).copyWith(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              infoAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (err, _) => Text(
                  t.filmInfoUnavailable,
                  style: AppTheme.body(
                    context,
                  ).copyWith(color: AppColors.textMuted),
                ),
                data: (info) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.overview, style: AppTheme.body(context)),
                    if (info.trailerUrl != null) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(info.trailerUrl!),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(t.watchTrailer),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Aggiungi l'icona "i" su `FilmCard`**

In `lib/features/showtimes/widgets/film_card.dart`, aggiungi l'import:
```dart
import '../../film_info/film_info_sheet.dart';
```

Trova il blocco che mostra `film.title` (dentro la `Row` con la locandina, prima colonna di testo) e avvolgilo in una `Row` con l'icona a fianco:
```dart
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              film.title,
                              style: AppTheme.display(
                                context,
                              ).copyWith(fontSize: 20, height: 1),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.info_outline, size: 20),
                            tooltip: AppLocalizations.of(context).filmInfoTooltip,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => showFilmInfoSheet(
                              context,
                              FilmInfoArgs(
                                title: film.title,
                                posterImageSrc: film.posterImageSrc,
                                runningTime: film.runningTime,
                              ),
                            ),
                          ),
                        ],
                      ),
```
(sostituisce il singolo widget `Text(film.title, ...)` esistente in quel punto - `AppLocalizations` è già importato in questo file).

- [ ] **Step 3: Verifica che il progetto compili**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Esegui l'intera suite di test**

Run: `flutter test`
Expected: PASS, nessuna regressione.

- [ ] **Step 5: Commit**

```bash
git add lib/features/film_info/film_info_sheet.dart lib/features/showtimes/widgets/film_card.dart
git commit -m "Aggiungi il bottom sheet trama/trailer e il tasto info su FilmCard"
```

---

### Task 6: Icona info su `SeatMapScreen`

**Files:**
- Modify: `lib/features/seat_map/seat_map_provider.dart`
- Modify: `lib/features/seat_map/seat_map_screen.dart`
- Modify: `lib/features/showtimes/widgets/film_card.dart`

**Interfaces:**
- Consumes: `FilmInfoArgs`, `showFilmInfoSheet` (Task 5).
- Produces: `SeatMapArgs` guadagna `posterImageSrc`/`runningTime` (entrambi `final`, nullable, stesso tipo dei campi omonimi su `Film`).

- [ ] **Step 1: Estendi `SeatMapArgs`**

In `lib/features/seat_map/seat_map_provider.dart`, il costruttore/campi di `SeatMapArgs` diventano:
```dart
class SeatMapArgs {
  const SeatMapArgs({
    required this.cinema,
    required this.filmId,
    required this.filmTitle,
    required this.posterImageSrc,
    required this.runningTime,
    required this.showingGroups,
    required this.initialSessionId,
  });

  final Cinema cinema;
  final String filmId;
  final String filmTitle;
  final String? posterImageSrc;
  final int? runningTime;
  final List<ShowingGroup> showingGroups;
  final String initialSessionId;
}
```

- [ ] **Step 2: Passa i due nuovi campi dal punto in cui `SeatMapArgs` viene costruito**

In `lib/features/showtimes/widgets/film_card.dart`, dentro `_openSeatMap`, aggiorna la costruzione di `SeatMapArgs`:
```dart
  void _openSeatMap(BuildContext context, WidgetRef ref, Session session) {
    ref.read(seatMapProvider((cinema, session)).future).ignore();
    context.push(
      '/seat-map',
      extra: SeatMapArgs(
        cinema: cinema,
        filmId: film.filmId,
        filmTitle: film.title,
        posterImageSrc: film.posterImageSrc,
        runningTime: film.runningTime,
        showingGroups: film.showingGroups,
        initialSessionId: session.sessionId,
      ),
    );
  }
```

- [ ] **Step 3: Verifica che il progetto compili**

`film_card.dart` (Step 2) è l'unico punto del codice che costruisce
`SeatMapArgs` (verificato con `grep -rn "SeatMapArgs(" lib/`), quindi non
serve aggiornare altri file.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Aggiungi l'icona "i" sull'AppBar di `SeatMapScreen`**

In `lib/features/seat_map/seat_map_screen.dart`, aggiungi l'import:
```dart
import '../film_info/film_info_sheet.dart';
```

Nel metodo `build`, l'`AppBar` diventa:
```dart
      appBar: AppBar(
        title: Text(
          widget.args.filmTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: AppLocalizations.of(context).filmInfoTooltip,
            onPressed: () => showFilmInfoSheet(
              context,
              FilmInfoArgs(
                title: widget.args.filmTitle,
                posterImageSrc: widget.args.posterImageSrc,
                runningTime: widget.args.runningTime,
              ),
            ),
          ),
        ],
      ),
```
(`AppLocalizations` è già importato in questo file).

- [ ] **Step 5: Verifica che il progetto compili**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Esegui l'intera suite di test**

Run: `flutter test`
Expected: PASS, nessuna regressione.

- [ ] **Step 7: Commit**

```bash
git add lib/features/seat_map/seat_map_provider.dart lib/features/seat_map/seat_map_screen.dart lib/features/showtimes/widgets/film_card.dart
git commit -m "Aggiungi il tasto info anche sulla schermata mappa posti"
```

---

### Task 7: Pulizia della cache all'avvio (60 giorni)

**Files:**
- Modify: `lib/app.dart`

**Interfaces:**
- Consumes: `filmInfoStoreProvider` (Task 2), `clockProvider` (esistente).

- [ ] **Step 1: Aggiungi la chiamata di pulizia in `_TheSpaceAppState.initState`**

In `lib/app.dart`, aggiungi l'import:
```dart
import 'core/storage/film_info_store.dart';
```

`initState` diventa:
```dart
  @override
  void initState() {
    super.initState();
    _lastKnownDayKey = todayKey(ref.read(clockProvider).now());
    _lifecycleListener = AppLifecycleListener(onResume: _checkForDayRollover);
    // Fire-and-forget, once per app process - same "housekeeping, not
    // something the UI waits on" shape as the update check. 60 days is
    // arbitrary but generous: this cache has no TTL otherwise (see
    // film_info_store.dart), only this startup sweep keeps it from growing
    // forever across months of use.
    ref
        .read(filmInfoStoreProvider)
        .purgeOlderThan(
          ref.read(clockProvider).now().subtract(const Duration(days: 60)),
        );
  }
```

- [ ] **Step 2: Verifica che il progetto compili**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Esegui l'intera suite di test**

Run: `flutter test`
Expected: PASS, nessuna regressione.

- [ ] **Step 4: Commit**

```bash
git add lib/app.dart
git commit -m "Pulisci la cache TMDb piu' vecchia di 60 giorni all'avvio"
```

---

### Task 8: Nota nel README sul `--dart-define` richiesto

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Aggiorna la sezione "Sviluppo"**

In `README.md`, il blocco `flutter build apk --release` nella sezione "## Sviluppo" diventa:
```bash
flutter pub get
flutter test
flutter run          # debug, su emulatore o device connesso
flutter build apk --release --dart-define=TMDB_READ_ACCESS_TOKEN=...  # trama/trailer film (facoltativo, senza la app funziona lo stesso)
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Documenta il dart-define TMDB_READ_ACCESS_TOKEN nel README"
```

---

### Task 9: Verifica manuale sul dispositivo

**Files:** nessuno (solo verifica).

- [ ] **Step 1: Build ed installazione**

Run:
```bash
flutter build apk --release --dart-define=TMDB_READ_ACCESS_TOKEN=<il-token-vero>
```
Poi installa sul device di test collegato (`adb install -r build/app/outputs/apk/release/app-release.apk`).

- [ ] **Step 2: Checklist manuale**

- [ ] Tocca l'icona "i" su una `FilmCard` nella lista spettacoli: il pannello si apre subito (locandina/titolo/durata visibili all'istante), poi mostra trama e (se esiste) il tasto trailer.
- [ ] Tocca "Guarda il trailer": si apre YouTube (app o browser), non un player interno.
- [ ] Chiudi il pannello, riapri lo stesso film: nessun nuovo caricamento visibile (dato già in cache, anche se qui è solo cache di sessione visto che l'app non è stata riavviata - la vera prova "persistente" è al passo successivo).
- [ ] Chiudi e riapri l'app, riapri lo stesso film: il pannello mostra subito i dati, senza spinner prolungato (letto dalla cache persistente, nessuna nuova chiamata TMDb).
- [ ] Apri l'icona "i" sulla schermata mappa posti per un film già visto in lista: stessa trama, nessuna nuova chiamata.
- [ ] Prova un film che TMDb non troverà (titolo inventato/palesemente sbagliato, se disponibile in programmazione, altrimenti salta questo punto): il pannello mostra "Descrizione non disponibile" invece di restare bloccato o vuoto.

---

## Self-Review

**Copertura spec:** ogni sezione della spec (`2026-08-24-tmdb-film-info-design.md`) ha un task corrispondente - fonte dati/matching (Task 1, 4), storage/cache (Task 2, 7), client (Task 3), punti di accesso UI (Task 5, 6), chiave API (Task 3, 4, 8), errori (Task 4, 5), test (Task 1, 2).

**Scan placeholder:** nessun TBD/TODO; ogni step ha codice reale, non descrizioni.

**Coerenza dei tipi:** `FilmInfo` (Task 2) usato identico in Task 4 (ritorno del provider) e Task 5 (`infoAsync.when(data: (info) => ...)`); `FilmInfoArgs` (Task 5) usato identico in Task 5 e 6; `TmdbSearchResult`/`parseTmdbSearchResult`/`parseTmdbTrailerKey` (Task 1) usati identici in Task 4; `SeatMapArgs` esteso in Task 6 con gli stessi nomi/tipi (`posterImageSrc`/`runningTime`) già usati su `Film` altrove nel codice.
