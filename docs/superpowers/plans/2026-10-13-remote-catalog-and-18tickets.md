# Remote Cinema Catalog, Navigability Check & 18tickets Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the cinema list be updated by a git push (no app release), never showing a cinema an installed app version can't handle, prove every new cinema works before it is published, and bring the dozens of missing 18tickets cinemas in - all before the next release (1.0.8).

**Architecture:** `assets/cinemas.json` stays the single source of truth and keeps shipping inside the app; the app additionally fetches the same file from GitHub raw at most once a day (ETag), validates it, caches it, and falls back to cache/bundled. Each catalog entry may carry `minAppVersion`; any entry an app version can't fully understand (unknown chain, unknown Webtic catalog source, too-new `minAppVersion`, malformed) is dropped instead of guessed. A live "navigability" check, built on the app's own `ChainApi` code, gates every new cinema. A new 18tickets discovery script produces candidates that only enter the catalog after passing that check.

**Tech Stack:** Flutter/Dart, Riverpod 3, Dio 5, shared_preferences, package_info_plus, flutter_test (live checks as a tagged, skipped-by-default test); Python 3 stdlib for catalog scripts.

**Spec:** No separate document - the decisions agreed with the user in conversation on 13 Oct 2026 are restated in **Context** below and are binding.

## Context (decisions agreed with the user)

- Remote list URL: `https://raw.githubusercontent.com/mauronofrio/cinema-disponibilita-posti/master/assets/cinemas.json` (the very file that ships). A push to master that changes it reaches users within a day.
- Fetch at most once per 24 h, conditional on ETag (`If-None-Match` → 304). Never block startup: the app shows cached-or-bundled immediately and swaps in a new list when a refresh succeeds.
- Safety: a downloaded list is used only if it parses, has no duplicate `chain:cinemaId` keys, and keeps at least half as many usable entries as the bundled list. Otherwise it is ignored (cache/bundled stay).
- A cache written by an older app version is discarded on upgrade (the new bundled list is at least as fresh at release time).
- **Version compatibility (user-raised problem):** every entry may declare `"minAppVersion": "1.0.9"`; an app older than that hides the entry. Entries without it are visible to all. Independently, any **unknown** value (chain, `webticCatalogSource`) makes the entry hidden - today `CinemaChain.fromJson` maps unknown strings to `theSpace` and `WebticCatalogSource.fromJson` to `fullSchedule`, which would make old apps call the wrong backend. This protection must ship in the first version that downloads the list (1.0.8) - installed apps can't be fixed afterwards. A missing/null `chain` keeps meaning The Space (legacy bundled entries).
- README shows the supported-cinema count (total + per platform); a test fails if it drifts from `cinemas.json`.
- **Navigability:** a cinema is publishable only if, on live data, (1) showing dates load and a future session exists within 7 days, (2) a seat map for a future session loads with seats (or an unnumbered sector), (3) that session has a booking link. Outcomes: ✅ navigable · ⚠️ programme only (user decides) · ❌ not navigable · ⏳ not verifiable now (nothing scheduled - e.g. a summer arena in October; retry later, never add blindly).
- 18tickets has no central venue list. Discovery = Certificate Transparency (Cert Spotter API) → circuit labels `*.X.18tickets.it` → each circuit's `https://X.18tickets.it/select_cinema?mandatory=true` lists venue hosts `Y.X.18tickets.it`; labels with no sub-hosts are single venues `X.18tickets.it`. A venue homepage gives its name in `<title>` and its address in the `maps.google.com/?q=ADDRESS` link. 18tickets answers HTTP 429 to bursts.
- **Test-after-release (user request):** one newly verified cinema is deliberately left out of the 1.0.8 list and added by a plain commit after the release, to prove the remote update end to end.

## Global Constraints

- Commit messages in **Italian**; **never** add a `Co-Authored-By` trailer. Do not push. No build artifacts on the Desktop.
- `flutter analyze` must print `No issues found!` and the full `flutter test` must pass before every commit. Live/network checks never run in the default `flutter test`.
- Catalog file format is exactly `json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"`, LF line endings; scripts open it with `newline="\n"`. Never reformat or reorder existing entries.
- Never remove or rename an existing `chain:cinemaId` (users' favorites are keyed on it).
- Network politeness: catalog scripts wait ≥ 3 s between 18tickets requests and back off 60 s on HTTP 429 (max 3 retries); Nominatim ≤ 1 req/s with the UA `CinemaDisponibilitaPosti-catalog/1.0 (github.com/mauronofrio/cinema-disponibilita-posti)`. GET only.
- Existing idioms: `Clock` injected (no `DateTime.now()` in app logic), Riverpod providers, `isNewerVersion` from `lib/core/update/update_checker.dart` for version comparison.
- Package import name: `thespace_companion`. Windows + Git Bash; write Dart/Python with an editor tool, not shell heredocs.

## Review Focus

1. **A list published while a user is offline / GitHub returns 5xx or garbage** → the app still shows the last good list instantly; nothing is cleared. Pinned in Task 2.
2. **An entry for a chain this version doesn't know** (e.g. a future chain) → hidden, never routed to The Space. Pinned in Task 1.
3. **A truncated or half-empty file pushed by mistake** → rejected by the half-of-bundled rule; the previous list stays. Pinned in Task 2.
4. **A cinema that shows dates but no future session** (end of day, seasonal) → ⏳ not verifiable, never ✅ and never ❌. Pinned in Task 4.
5. **A discovered 18tickets venue that is already in the catalog under a custom domain** (e.g. `monopoli.18tickets.it` = `monopoli.redcarpetcinema.it`) → reported as a possible duplicate, not a new candidate. Pinned in Task 5.

---

### Task 1: Safe, version-aware catalog parsing

**Files:**
- Modify: `lib/core/models/cinema.dart` (add `tryFromJson` to `CinemaChain` and `WebticCatalogSource`; add `Cinema.minAppVersion`; add `Cinema.tryFromJson`)
- Create: `lib/core/catalog/cinema_catalog_parser.dart`
- Modify: `lib/features/cinema_picker/cinema_list_provider.dart` (bundled list parsed through the new parser - temporary until Task 2)
- Test: `test/core/cinema_catalog_parser_test.dart`

**Interfaces:**
- Produces:
  ```dart
  // cinema.dart
  static CinemaChain? CinemaChain.tryFromJson(String? value);          // null/absent -> theSpace; unknown -> null
  static WebticCatalogSource? WebticCatalogSource.tryFromJson(String? v); // null/absent -> fullSchedule; unknown -> null
  final String? Cinema.minAppVersion;
  static Cinema? Cinema.tryFromJson(Map<String, dynamic> json);        // null on malformed/unknown values
  // cinema_catalog_parser.dart
  List<Cinema> parseCinemaCatalog(String body, {required String appVersion}); // throws FormatException if not a JSON list
  ```

- [ ] **Step 1: Write the failing tests** `test/core/cinema_catalog_parser_test.dart`

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/catalog/cinema_catalog_parser.dart';
import 'package:thespace_companion/core/models/cinema.dart';

Map<String, dynamic> _entry({
  String id = 'x',
  Object? chain = 'uci',
  Object? source,
  String? minAppVersion,
}) => {
  'cinemaId': id,
  'name': 'Cinema $id',
  'slug': id,
  'address': 'Via X 1',
  'lat': 41.0,
  'lng': 16.0,
  'chain': chain,
  'webticCatalogSource': ?source,
  'minAppVersion': ?minAppVersion,
};

String _list(List<Map<String, dynamic>> entries) => jsonEncode(entries);

void main() {
  test('the real bundled catalog parses completely - no entry is dropped', () {
    final raw = File('assets/cinemas.json').readAsStringSync();
    final all = jsonDecode(raw) as List<dynamic>;
    expect(parseCinemaCatalog(raw, appVersion: '1.0.7'), hasLength(all.length));
  });

  test('this is the actual regression case: an unknown chain is hidden, '
      'never routed to The Space as CinemaChain.fromJson used to do', () {
    final cinemas = parseCinemaCatalog(
      _list([_entry(id: 'a'), _entry(id: 'b', chain: 'aFutureChain')]),
      appVersion: '1.0.8',
    );
    expect(cinemas.map((c) => c.cinemaId), ['a']);
  });

  test('a missing chain still means The Space (legacy entries)', () {
    final c = parseCinemaCatalog(
      _list([_entry(chain: null)]),
      appVersion: '1.0.8',
    ).single;
    expect(c.chain, CinemaChain.theSpace);
  });

  test('an unknown Webtic catalog source is hidden, not guessed', () {
    final cinemas = parseCinemaCatalog(
      _list([
        _entry(id: 'ok', chain: 'webtic', source: 'programmingPage'),
        _entry(id: 'new', chain: 'webtic', source: 'aFutureSource'),
      ]),
      appVersion: '1.0.8',
    );
    expect(cinemas.map((c) => c.cinemaId), ['ok']);
  });

  test('minAppVersion hides an entry from older apps only', () {
    final body = _list([_entry(id: 'n', minAppVersion: '1.0.9')]);
    expect(parseCinemaCatalog(body, appVersion: '1.0.8'), isEmpty);
    expect(parseCinemaCatalog(body, appVersion: '1.0.9'), hasLength(1));
    expect(parseCinemaCatalog(body, appVersion: '1.1.0'), hasLength(1));
  });

  test('a malformed entry is skipped, the rest survive', () {
    final cinemas = parseCinemaCatalog(
      jsonEncode([
        _entry(id: 'good'),
        {'cinemaId': 'bad', 'name': 'No coordinates'},
        'not even a map',
      ]),
      appVersion: '1.0.8',
    );
    expect(cinemas.map((c) => c.cinemaId), ['good']);
  });

  test('a body that is not a JSON list is a FormatException', () {
    expect(
      () => parseCinemaCatalog('{"oops": true}', appVersion: '1.0.8'),
      throwsFormatException,
    );
    expect(
      () => parseCinemaCatalog('<html>', appVersion: '1.0.8'),
      throwsFormatException,
    );
  });
}
```

(The `'key': ?value` null-aware map element needs Dart ≥ 3.8; if `flutter analyze` rejects it, use `if (source != null) 'webticCatalogSource': source,` instead.)

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/core/cinema_catalog_parser_test.dart` → FAIL (file `cinema_catalog_parser.dart` missing).

- [ ] **Step 3: Implement**

In `lib/core/models/cinema.dart`:

```dart
  // inside enum CinemaChain, next to fromJson:
  /// Like [fromJson], but an *unknown* value yields null instead of falling
  /// back to The Space - a catalog downloaded from GitHub may name a chain
  /// added in a later app version, and routing it to The Space's backend
  /// would just produce errors. Missing/null still means The Space: the
  /// oldest bundled entries carry no `chain` at all.
  static CinemaChain? tryFromJson(String? value) => switch (value) {
    null => CinemaChain.theSpace,
    'theSpace' => CinemaChain.theSpace,
    'uci' => CinemaChain.uci,
    'eighteenTickets' => CinemaChain.eighteenTickets,
    'webtic' => CinemaChain.webtic,
    'twoTickets' => CinemaChain.twoTickets,
    _ => null,
  };
```

```dart
  // inside enum WebticCatalogSource, next to fromJson:
  /// Same idea as [CinemaChain.tryFromJson]: absent means the default
  /// [fullSchedule], an unknown value means "a newer app version's source"
  /// and yields null so the entry is hidden.
  static WebticCatalogSource? tryFromJson(String? value) => switch (value) {
    null => WebticCatalogSource.fullSchedule,
    'fullSchedule' => WebticCatalogSource.fullSchedule,
    'programmingPage' => WebticCatalogSource.programmingPage,
    'filmSchedulePages' => WebticCatalogSource.filmSchedulePages,
    'fullSchedulePortal' => WebticCatalogSource.fullSchedulePortal,
    'madisonProgrammingPage' => WebticCatalogSource.madisonProgrammingPage,
    _ => null,
  };
```

Add to `Cinema` the optional constructor param `this.minAppVersion` and the field:

```dart
  /// The oldest app version that can show this cinema (e.g. "1.0.9" for a
  /// venue that needed code shipped in 1.0.9). Null for "every version".
  /// See `parseCinemaCatalog`.
  final String? minAppVersion;
```

and the factory:

```dart
  /// [fromJson] for untrusted input (the catalog downloaded from GitHub):
  /// null instead of a throw for a malformed entry, and null for any value
  /// this app version doesn't understand (see [CinemaChain.tryFromJson]).
  static Cinema? tryFromJson(Map<String, dynamic> json) {
    try {
      // Inside the try: a non-string `chain` (e.g. a number) is malformed
      // input too, and must drop the entry rather than throw.
      final chain = CinemaChain.tryFromJson(json['chain'] as String?);
      final source = WebticCatalogSource.tryFromJson(
        json['webticCatalogSource'] as String?,
      );
      if (chain == null || source == null) return null;
      return Cinema(
        cinemaId: json['cinemaId'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        address: json['address'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        chain: chain,
        webticLocalId: json['webticLocalId'] as int?,
        host: json['host'] as String?,
        hasSeatMap: json['hasSeatMap'] as bool? ?? true,
        scheduleFromFilmPages: json['scheduleFromFilmPages'] as bool? ?? false,
        webticCatalogSource: source,
        minAppVersion: json['minAppVersion'] as String?,
      );
    } on TypeError {
      return null;
    }
  }
```

Keep `Cinema.fromJson` (existing callers/tests) but make it delegate: `factory Cinema.fromJson(Map<String, dynamic> json) => tryFromJson(json) ?? (throw FormatException('Invalid cinema entry: ${json['cinemaId']}'));` - check that every existing test still passes; if a test relied on the old unknown→theSpace behaviour, update it and say so in the report.

`lib/core/catalog/cinema_catalog_parser.dart`:

```dart
import 'dart:convert';

import '../models/cinema.dart';
import '../update/update_checker.dart' show isNewerVersion;

/// Parses a cinema catalog body (bundled asset or downloaded from GitHub)
/// into the cinemas *this app version* can actually show. Malformed entries,
/// entries with values this version doesn't know, and entries whose
/// `minAppVersion` is newer than [appVersion] are dropped - never guessed.
/// Throws [FormatException] only when the body isn't a JSON list at all.
List<Cinema> parseCinemaCatalog(String body, {required String appVersion}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    rethrow;
  }
  if (decoded is! List) {
    throw const FormatException('Cinema catalog is not a JSON list');
  }
  final result = <Cinema>[];
  for (final raw in decoded) {
    if (raw is! Map<String, dynamic>) continue;
    final cinema = Cinema.tryFromJson(raw);
    if (cinema == null) continue;
    final min = cinema.minAppVersion;
    if (min != null && isNewerVersion(current: appVersion, latest: min)) {
      continue;
    }
    result.add(cinema);
  }
  return result;
}
```

In `cinema_list_provider.dart` change the bundled load to `parseCinemaCatalog(raw, appVersion: version)` where `version` comes from a new provider in the same file:

```dart
/// The installed app's version ("1.0.8"), used to hide catalog entries that
/// need a newer one. Overridden in tests.
final appVersionProvider = FutureProvider<String>((ref) async {
  return (await PackageInfo.fromPlatform()).version;
});
```

(import `package:package_info_plus/package_info_plus.dart`). Task 2 replaces the body of `cinemaListProvider`; here it only switches parser.

- [ ] **Step 4: Run** the test file → PASS; `flutter analyze`; full `flutter test` → green.

- [ ] **Step 5: Commit**

```bash
git add lib/core/models/cinema.dart lib/core/catalog/cinema_catalog_parser.dart lib/features/cinema_picker/cinema_list_provider.dart test/core/cinema_catalog_parser_test.dart
git commit -m "Scarta dal catalogo i cinema che questa versione non sa gestire, invece di indovinare"
```

---

### Task 2: Remote catalog with cache, ETag and fallback

**Files:**
- Create: `lib/core/catalog/cinema_catalog_repository.dart`
- Modify: `lib/features/cinema_picker/cinema_list_provider.dart`
- Test: `test/core/cinema_catalog_repository_test.dart`

**Interfaces:**
- Consumes: `parseCinemaCatalog`, `appVersionProvider` (Task 1), `Clock`/`clockProvider` (`lib/core/date/clock.dart`).
- Produces:
  ```dart
  class CinemaCatalogRepository {
    CinemaCatalogRepository({required Dio dio, required Clock clock, required Future<String> Function() loadBundled});
    static const remoteUrl = 'https://raw.githubusercontent.com/mauronofrio/cinema-disponibilita-posti/master/assets/cinemas.json';
    static const checkInterval = Duration(hours: 24);
    Future<List<Cinema>> load({required String appVersion});            // never throws for network reasons
    Future<bool> refreshIfStale({required String appVersion});          // true if a new list was stored
  }
  final cinemaCatalogRepositoryProvider = Provider<CinemaCatalogRepository>(...);
  ```

- [ ] **Step 1: Write the failing tests** `test/core/cinema_catalog_repository_test.dart`

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thespace_companion/core/catalog/cinema_catalog_repository.dart';
import 'package:thespace_companion/core/date/clock.dart';

class _Clock extends Clock {
  _Clock(this.value);
  DateTime value;
  @override
  DateTime now() => value;
}

/// Plays GitHub raw: serves [body] with an ETag, answers 304 to a matching
/// If-None-Match, or fails/returns garbage when told to.
class _FakeGitHub implements HttpClientAdapter {
  String body = _catalog(4);
  String etag = '"v1"';
  int status = 200;
  bool fail = false;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    if (fail) throw DioException.connectionError(requestOptions: options, reason: 'offline');
    if (options.headers['If-None-Match'] == etag) {
      return ResponseBody.fromString('', 304);
    }
    return ResponseBody.fromString(body, status, headers: {
      'etag': [etag],
      'content-type': ['text/plain; charset=utf-8'],
    });
  }

  @override
  void close({bool force = false}) {}
}

String _catalog(int n) => jsonEncode([
  for (var i = 0; i < n; i++)
    {
      'cinemaId': 'c$i',
      'name': 'Cinema $i',
      'slug': 'c$i',
      'address': 'Via $i',
      'lat': 41.0,
      'lng': 16.0,
      'chain': 'uci',
    },
]);

void main() {
  late _FakeGitHub github;
  late _Clock clock;
  late CinemaCatalogRepository repo;

  CinemaCatalogRepository build() => CinemaCatalogRepository(
    dio: Dio()..httpClientAdapter = github,
    clock: clock,
    loadBundled: () async => _catalog(4),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    github = _FakeGitHub();
    clock = _Clock(DateTime(2026, 10, 20, 9));
    repo = build();
  });

  test('first run with no cache: bundled list', () async {
    expect(await repo.load(appVersion: '1.0.8'), hasLength(4));
  });

  test('a successful refresh is used from then on', () async {
    github.body = _catalog(5);
    expect(await repo.refreshIfStale(appVersion: '1.0.8'), isTrue);
    expect(await build().load(appVersion: '1.0.8'), hasLength(5));
  });

  test('at most one check per 24h, and a 304 changes nothing', () async {
    github.body = _catalog(5);
    await repo.refreshIfStale(appVersion: '1.0.8');
    expect(await repo.refreshIfStale(appVersion: '1.0.8'), isFalse);
    expect(github.requests, 1);
    clock.value = clock.value.add(const Duration(hours: 25));
    expect(await repo.refreshIfStale(appVersion: '1.0.8'), isFalse); // 304
    expect(github.requests, 2);
    expect(await repo.load(appVersion: '1.0.8'), hasLength(5));
  });

  test('Review Focus 1: offline or a 5xx keeps the last good list and '
      'retries on the next launch', () async {
    github.body = _catalog(5);
    await repo.refreshIfStale(appVersion: '1.0.8');
    clock.value = clock.value.add(const Duration(hours: 25));
    github.fail = true;
    expect(await repo.refreshIfStale(appVersion: '1.0.8'), isFalse);
    expect(await repo.load(appVersion: '1.0.8'), hasLength(5));
    github
      ..fail = false
      ..status = 503
      ..etag = '"v2"';
    expect(await repo.refreshIfStale(appVersion: '1.0.8'), isFalse);
    expect(await repo.load(appVersion: '1.0.8'), hasLength(5));
  });

  test('Review Focus 3: a truncated / mostly-empty list is rejected', () async {
    github.body = _catalog(1); // bundled has 4 -> below half
    expect(await repo.refreshIfStale(appVersion: '1.0.8'), isFalse);
    expect(await repo.load(appVersion: '1.0.8'), hasLength(4));
    github
      ..body = '<html>Not Found</html>'
      ..etag = '"v3"';
    clock.value = clock.value.add(const Duration(hours: 25));
    expect(await repo.refreshIfStale(appVersion: '1.0.8'), isFalse);
    expect(await repo.load(appVersion: '1.0.8'), hasLength(4));
  });

  test('a list with duplicate chain:cinemaId keys is rejected', () async {
    final dup = jsonDecode(_catalog(4)) as List<dynamic>
      ..add((jsonDecode(_catalog(1)) as List<dynamic>).first);
    github.body = jsonEncode(dup);
    expect(await repo.refreshIfStale(appVersion: '1.0.8'), isFalse);
  });

  test('a cache written by an older app version is discarded on upgrade', () async {
    github.body = _catalog(5);
    await repo.refreshIfStale(appVersion: '1.0.8');
    expect(await build().load(appVersion: '1.0.9'), hasLength(4));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/cinema_catalog_repository_test.dart` → FAIL (file missing).

- [ ] **Step 3: Implement** `lib/core/catalog/cinema_catalog_repository.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../date/clock.dart';
import '../models/cinema.dart';
import 'cinema_catalog_parser.dart';

/// The cinema list: bundled in the app, and refreshed from the very same
/// file on GitHub at most once a day, so a cinema can be added with a
/// commit instead of a release. Every downloaded list is validated before
/// use and the last good one is kept - a bad push or a network problem can
/// never leave a user with fewer cinemas than they had.
class CinemaCatalogRepository {
  CinemaCatalogRepository({
    required Dio dio,
    required Clock clock,
    required Future<String> Function() loadBundled,
  }) : _dio = dio,
       _clock = clock,
       _loadBundled = loadBundled;

  static const remoteUrl =
      'https://raw.githubusercontent.com/mauronofrio/cinema-disponibilita-posti/master/assets/cinemas.json';
  static const checkInterval = Duration(hours: 24);

  static const _bodyKey = 'cinema_catalog_body';
  static const _etagKey = 'cinema_catalog_etag';
  static const _checkedAtKey = 'cinema_catalog_checked_at';
  static const _appVersionKey = 'cinema_catalog_app_version';

  final Dio _dio;
  final Clock _clock;
  final Future<String> Function() _loadBundled;

  Future<List<Cinema>> _bundled(String appVersion) async =>
      parseCinemaCatalog(await _loadBundled(), appVersion: appVersion);

  /// Null when [body] must not replace what the user has: unparseable,
  /// duplicate keys, or fewer than half the bundled cinemas (a truncated or
  /// emptied file pushed by mistake).
  List<Cinema>? _accept(String body, String appVersion, int bundledCount) {
    final List<Cinema> cinemas;
    try {
      cinemas = parseCinemaCatalog(body, appVersion: appVersion);
    } on FormatException {
      return null;
    }
    final keys = {for (final c in cinemas) '${c.chain.name}:${c.cinemaId}'};
    if (keys.length != cinemas.length) return null;
    if (cinemas.length * 2 < bundledCount) return null;
    return cinemas;
  }

  /// A new app version ships a bundled list at least as fresh as any cache
  /// an older version downloaded - so a cache stamped with a different
  /// version is dropped. No stamp at all just means "nothing cached yet".
  Future<void> _dropCacheFromOtherVersion(
    SharedPreferences prefs,
    String appVersion,
  ) async {
    final stamped = prefs.getString(_appVersionKey);
    if (stamped != null && stamped != appVersion) await _clear(prefs);
  }

  Future<List<Cinema>> load({required String appVersion}) async {
    final bundled = await _bundled(appVersion);
    final prefs = await SharedPreferences.getInstance();
    await _dropCacheFromOtherVersion(prefs, appVersion);
    final cached = prefs.getString(_bodyKey);
    if (cached == null) return bundled;
    return _accept(cached, appVersion, bundled.length) ?? bundled;
  }

  Future<bool> refreshIfStale({required String appVersion}) async {
    final prefs = await SharedPreferences.getInstance();
    await _dropCacheFromOtherVersion(prefs, appVersion);
    final checkedAt = DateTime.tryParse(prefs.getString(_checkedAtKey) ?? '');
    final now = _clock.now();
    if (checkedAt != null && now.difference(checkedAt) < checkInterval) {
      return false;
    }
    final etag = prefs.getString(_etagKey);
    final Response<String> response;
    try {
      response = await _dio.get<String>(
        remoteUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {if (etag != null) 'If-None-Match': etag},
          validateStatus: (s) => s != null && s < 600,
        ),
      );
    } on DioException {
      return false; // offline: try again next launch, keep what we have
    }
    if (response.statusCode == 304) {
      await prefs.setString(_checkedAtKey, now.toIso8601String());
      return false;
    }
    if (response.statusCode != 200) return false;
    final bundled = await _bundled(appVersion);
    final body = response.data ?? '';
    final accepted = _accept(body, appVersion, bundled.length);
    await prefs.setString(_checkedAtKey, now.toIso8601String());
    await prefs.setString(_appVersionKey, appVersion);
    if (accepted == null) return false;
    await prefs.setString(_bodyKey, body);
    final newEtag = response.headers.value('etag');
    if (newEtag != null) await prefs.setString(_etagKey, newEtag);
    return true;
  }

  Future<void> _clear(SharedPreferences prefs) async {
    await prefs.remove(_bodyKey);
    await prefs.remove(_etagKey);
    await prefs.remove(_checkedAtKey);
    await prefs.remove(_appVersionKey);
  }
}

final cinemaCatalogRepositoryProvider = Provider<CinemaCatalogRepository>((ref) {
  return CinemaCatalogRepository(
    dio: Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
      ),
    ),
    clock: ref.watch(clockProvider),
    loadBundled: () => rootBundle.loadString('assets/cinemas.json'),
  );
});
```

Version stamp semantics: the cache is stamped with the app version that wrote it (`refreshIfStale` stamps on every completed check); a stamp from a *different* version drops the cache, no stamp means nothing cached. Walk the seven tests against this before running them: "successful refresh is used" (stamp 1.0.8, load 1.0.8 → cache), "older version discarded" (stamp 1.0.8, load 1.0.9 → bundled).

`cinema_list_provider.dart`, replace `cinemaListProvider` with:

```dart
/// Every cinema this app version can show: cached-or-bundled immediately,
/// then - at most once a day - refreshed from GitHub in the background
/// (see CinemaCatalogRepository). When a refresh brings a new valid list
/// the provider rebuilds itself, so the picker updates without a restart.
final cinemaListProvider = FutureProvider<List<Cinema>>((ref) async {
  final repo = ref.watch(cinemaCatalogRepositoryProvider);
  final version = await ref.watch(appVersionProvider.future);
  final cinemas = await repo.load(appVersion: version);
  repo.refreshIfStale(appVersion: version).then((changed) {
    if (changed) ref.invalidateSelf();
  }).ignore();
  return cinemas;
});
```

(remove the now-unused `dart:convert`/`rootBundle` imports if unused).

- [ ] **Step 4: Run** the test file → PASS; `flutter analyze`; full `flutter test` → green (existing picker/favorites tests that read `cinemaListProvider` may now need `appVersionProvider` overridden and `SharedPreferences.setMockInitialValues({})` - fix them in the same commit and list them in the report).

- [ ] **Step 5: Commit**

```bash
git add lib/core/catalog/cinema_catalog_repository.dart lib/features/cinema_picker/cinema_list_provider.dart test/core/cinema_catalog_repository_test.dart
git commit -m "Aggiorna l'elenco dei cinema da GitHub una volta al giorno, con cache e ripiego sicuro"
```

---

### Task 3: Cinema count in the README, kept honest by a test

**Files:**
- Create: `tools/update_readme_counts.py`
- Modify: `README.md` (insert the counts block right under `## Cinema supportati`)
- Test: `test/core/readme_counts_test.dart`

**Interfaces:**
- Produces the README block (exact format, between the two marker lines):
  ```
  <!-- cinema-counts:start -->
  **N cinema supportati** · The Space A · UCI B · 18tickets C · Webtic D · 2Tickets E
  <!-- cinema-counts:end -->
  ```
  where N = total entries in `assets/cinemas.json` and A..E count entries by `chain` (missing chain = The Space). All entries are counted, including ones with `minAppVersion`.

- [ ] **Step 1: Write the failing test** `test/core/readme_counts_test.dart`

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Must produce exactly what tools/update_readme_counts.py writes.
String expectedBlock() {
  final entries = jsonDecode(File('assets/cinemas.json').readAsStringSync())
      as List<dynamic>;
  final counts = <String, int>{};
  for (final e in entries.cast<Map<String, dynamic>>()) {
    final chain = (e['chain'] as String?) ?? 'theSpace';
    counts[chain] = (counts[chain] ?? 0) + 1;
  }
  int n(String k) => counts[k] ?? 0;
  return '<!-- cinema-counts:start -->\n'
      '**${entries.length} cinema supportati** · The Space ${n('theSpace')} · '
      'UCI ${n('uci')} · 18tickets ${n('eighteenTickets')} · '
      'Webtic ${n('webtic')} · 2Tickets ${n('twoTickets')}\n'
      '<!-- cinema-counts:end -->';
}

void main() {
  test('README cinema counts match assets/cinemas.json - if this fails, run '
      'python tools/update_readme_counts.py', () {
    final readme = File('README.md').readAsStringSync().replaceAll('\r\n', '\n');
    expect(readme, contains(expectedBlock()));
  });
}
```

- [ ] **Step 2: Run** → FAIL (no block in README).

- [ ] **Step 3: Implement** `tools/update_readme_counts.py`

```python
"""Rewrites the cinema-counts block in README.md from assets/cinemas.json.
Run after every catalog change; test/core/readme_counts_test.dart fails
until you do."""
import json
import re

entries = json.load(open("assets/cinemas.json", encoding="utf-8"))
counts = {}
for e in entries:
    chain = e.get("chain") or "theSpace"
    counts[chain] = counts.get(chain, 0) + 1
n = lambda k: counts.get(k, 0)
block = (
    "<!-- cinema-counts:start -->\n"
    f"**{len(entries)} cinema supportati** · The Space {n('theSpace')} · "
    f"UCI {n('uci')} · 18tickets {n('eighteenTickets')} · "
    f"Webtic {n('webtic')} · 2Tickets {n('twoTickets')}\n"
    "<!-- cinema-counts:end -->"
)
readme = open("README.md", encoding="utf-8").read()
pattern = re.compile(r"<!-- cinema-counts:start -->.*?<!-- cinema-counts:end -->", re.S)
if pattern.search(readme):
    readme = pattern.sub(lambda _: block, readme)
else:
    readme = readme.replace("## Cinema supportati\n", "## Cinema supportati\n\n" + block + "\n", 1)
open("README.md", "w", encoding="utf-8", newline="\n").write(readme)
print(block)
```

Run it: `PYTHONIOENCODING=utf-8 python tools/update_readme_counts.py`. Check `git diff README.md` touches only the inserted block (if README.md has CRLF line endings today, preserve them: detect and write back with the same newline style, and say so in the report).

- [ ] **Step 4: Run** the test → PASS; `flutter analyze`; full `flutter test` → green.

- [ ] **Step 5: Commit**

```bash
git add tools/update_readme_counts.py README.md test/core/readme_counts_test.dart
git commit -m "Mostra nel README il numero di cinema supportati, verificato da un test"
```

---

### Task 4: Navigability check (live, on the app's own code)

**Files:**
- Create: `test/support/navigability.dart` (pure logic, offline-testable)
- Create: `test/core/navigability_test.dart` (offline unit tests with a fake `ChainApi`)
- Create: `test/live/verify_navigability_test.dart` (the live runner, tagged `live`)
- Create: `dart_test.yaml`
- Modify: `README.md` "## Sviluppo" (how to run it)

**Interfaces:**
- Produces:
  ```dart
  enum Navigability { navigable, programmeOnly, notNavigable, notVerifiableNow }
  class NavigabilityResult { final Cinema cinema; final Navigability verdict; final String reason; Map<String, dynamic> toJson(); }
  Future<NavigabilityResult> checkNavigability(ChainApi api, Cinema cinema, DateTime now);
  ```
  Live runner inputs (all `--dart-define`): `VERIFY_FILE` (default `assets/cinemas.json`), `VERIFY_CHAIN` (optional chain name filter), `VERIFY_IDS` (optional comma list of cinemaIds), `VERIFY_DELAY_MS` (default 4000), `VERIFY_REPORT` (default `build/navigability_report.json`).

- [ ] **Step 1: Write the failing offline tests** `test/core/navigability_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/chains/chain_api.dart';
import 'package:thespace_companion/core/models/cinema.dart';
import 'package:thespace_companion/core/models/film.dart';
import 'package:thespace_companion/core/models/seat_map.dart';
import 'package:thespace_companion/core/models/showing_date.dart';

import '../support/navigability.dart';

final _now = DateTime(2026, 10, 20, 18);

Session _session(DateTime start, {String? booking = 'https://x/buy'}) => Session(
  sessionId: '${start.millisecondsSinceEpoch}',
  startTime: start,
  endTime: start.add(const Duration(hours: 2)),
  screenName: 'Sala 1',
  isSoldOut: false,
  formattedPrice: null,
  isPriceVisible: false,
  attributes: const [],
  bookingPath: booking,
);

SeatMap _seats(int n) => SeatMap(
  screenLabel: '',
  totalRows: n == 0 ? 0 : 1,
  totalColumns: n,
  rows: [
    if (n > 0)
      SeatRow(
        rowLabel: 'A',
        rowIndex: 0,
        seats: [
          for (var i = 0; i < n; i++)
            Seat(rowIndex: 0, columnIndex: i, name: 'A$i',
                status: SeatStatus.available, areaCategoryCode: ''),
        ],
      ),
  ],
  areaCategories: const [],
);

class _Api implements ChainApi {
  _Api({this.dates, this.sessions = const [], this.seatMap, this.datesError, this.seatError});
  final List<ShowingDate>? dates;
  final List<Session> sessions;
  final SeatMap? seatMap;
  final Object? datesError;
  final Object? seatError;

  @override
  Future<List<ShowingDate>> getShowingDates(Cinema c) async {
    if (datesError != null) throw datesError!;
    return dates ?? [ShowingDate(date: DateTime(2026, 10, 20), hasShowings: true)];
  }

  @override
  Future<List<Film>> getFilmsForDay(Cinema c, DateTime day) async => [
    Film(filmId: 'f', title: 'F', posterImageSrc: null, runningTime: 100,
        showingGroups: [ShowingGroup(date: DateTime(2026, 10, 20), sessions: sessions)]),
  ];

  @override
  Future<SeatMap> getSeatMap(Cinema c, Session s) async {
    if (seatError != null) throw seatError!;
    return seatMap ?? _seats(10);
  }
}

const _cinema = Cinema(cinemaId: 'c', name: 'C', slug: 'c', address: 'a',
    lat: 41, lng: 16, chain: CinemaChain.eighteenTickets);

void main() {
  test('dates, a future session, seats and a booking link: navigable', () async {
    final r = await checkNavigability(
      _Api(sessions: [_session(_now.add(const Duration(hours: 2)))]), _cinema, _now);
    expect(r.verdict, Navigability.navigable);
  });

  test('the programme fails to load: not navigable', () async {
    final r = await checkNavigability(_Api(datesError: Exception('boom')), _cinema, _now);
    expect(r.verdict, Navigability.notNavigable);
  });

  test('Review Focus 4: dates but no future session (end of the day, '
      'season over) is "not verifiable now" - never navigable, never broken', () async {
    final r = await checkNavigability(
      _Api(sessions: [_session(_now.subtract(const Duration(hours: 3)))]), _cinema, _now);
    expect(r.verdict, Navigability.notVerifiableNow);
    final none = await checkNavigability(_Api(dates: const []), _cinema, _now);
    expect(none.verdict, Navigability.notVerifiableNow);
  });

  test('seat map fails or is empty: programme only', () async {
    final s = [_session(_now.add(const Duration(hours: 2)))];
    expect((await checkNavigability(_Api(sessions: s, seatError: Exception('x')), _cinema, _now)).verdict,
        Navigability.programmeOnly);
    expect((await checkNavigability(_Api(sessions: s, seatMap: _seats(0)), _cinema, _now)).verdict,
        Navigability.programmeOnly);
  });

  test('no booking link: programme only', () async {
    final r = await checkNavigability(
      _Api(sessions: [_session(_now.add(const Duration(hours: 2)), booking: null)]), _cinema, _now);
    expect(r.verdict, Navigability.programmeOnly);
  });
}
```

- [ ] **Step 2: Run** `flutter test test/core/navigability_test.dart` → FAIL (`navigability.dart` missing).

- [ ] **Step 3: Implement** `test/support/navigability.dart`

```dart
import 'package:thespace_companion/core/chains/chain_api.dart';
import 'package:thespace_companion/core/models/cinema.dart';
import 'package:thespace_companion/core/models/film.dart';

enum Navigability { navigable, programmeOnly, notNavigable, notVerifiableNow }

class NavigabilityResult {
  const NavigabilityResult(this.cinema, this.verdict, this.reason);
  final Cinema cinema;
  final Navigability verdict;
  final String reason;

  Map<String, dynamic> toJson() => {
    'chain': cinema.chain.name,
    'cinemaId': cinema.cinemaId,
    'name': cinema.name,
    'verdict': verdict.name,
    'reason': reason,
  };
}

/// Whether [cinema] works end to end in the app, judged by the app's own
/// [ChainApi] on live data: programme within 7 days, a future session whose
/// seat map has seats (or an unnumbered sector), and a booking link. A
/// cinema with nothing scheduled right now can't be judged either way.
Future<NavigabilityResult> checkNavigability(
  ChainApi api,
  Cinema cinema,
  DateTime now,
) async {
  NavigabilityResult r(Navigability v, String why) =>
      NavigabilityResult(cinema, v, why);
  final today = DateTime(now.year, now.month, now.day);
  final horizon = today.add(const Duration(days: 7));

  final List<DateTime> days;
  try {
    days = [
      for (final d in await api.getShowingDates(cinema))
        if (d.hasShowings && !d.date.isBefore(today) && d.date.isBefore(horizon))
          DateTime(d.date.year, d.date.month, d.date.day),
    ];
  } catch (e) {
    return r(Navigability.notNavigable, 'programmazione: $e');
  }
  if (days.isEmpty) {
    return r(Navigability.notVerifiableNow, 'nessuna programmazione nei prossimi 7 giorni');
  }

  final future = <Session>[];
  try {
    for (final day in days) {
      for (final film in await api.getFilmsForDay(cinema, day)) {
        future.addAll(film.sessionsOn(day).where((s) => s.startTime.isAfter(now)));
      }
      if (future.isNotEmpty) break;
    }
  } catch (e) {
    return r(Navigability.notNavigable, 'film: $e');
  }
  if (future.isEmpty) {
    return r(Navigability.notVerifiableNow, 'nessuno spettacolo futuro nei prossimi 7 giorni');
  }
  future.sort((a, b) => a.startTime.compareTo(b.startTime));

  if (!cinema.hasSeatMap) {
    return r(Navigability.programmeOnly, 'cinema senza mappa posti per scelta');
  }
  final session = future.first;
  try {
    final map = await api.getSeatMap(cinema, session);
    if (map.rows.isEmpty && map.unnumberedSectors.isEmpty) {
      return r(Navigability.programmeOnly, 'mappa posti vuota');
    }
  } catch (e) {
    return r(Navigability.programmeOnly, 'mappa posti: $e');
  }
  if (session.bookingPath == null) {
    return r(Navigability.programmeOnly, 'manca il link di acquisto');
  }
  return r(Navigability.navigable, 'ok');
}
```

`dart_test.yaml`:

```yaml
tags:
  live:
    skip: "Live network check. Run: flutter test --run-skipped --tags live test/live"
```

`test/live/verify_navigability_test.dart`:

```dart
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/catalog/cinema_catalog_parser.dart';
import 'package:thespace_companion/core/chains/chain_registry.dart';

import '../support/navigability.dart';

const _file = String.fromEnvironment('VERIFY_FILE', defaultValue: 'assets/cinemas.json');
const _chain = String.fromEnvironment('VERIFY_CHAIN');
const _ids = String.fromEnvironment('VERIFY_IDS');
const _delayMs = int.fromEnvironment('VERIFY_DELAY_MS', defaultValue: 4000);
const _report = String.fromEnvironment('VERIFY_REPORT', defaultValue: 'build/navigability_report.json');

void main() {
  test('navigability of the selected cinemas (live)', () async {
    // Version high enough that minAppVersion never hides a candidate here.
    var cinemas = parseCinemaCatalog(File(_file).readAsStringSync(), appVersion: '999.0.0');
    if (_chain.isNotEmpty) cinemas = cinemas.where((c) => c.chain.name == _chain).toList();
    if (_ids.isNotEmpty) {
      final ids = _ids.split(',').map((s) => s.trim()).toSet();
      cinemas = cinemas.where((c) => ids.contains(c.cinemaId)).toList();
    }
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final results = <NavigabilityResult>[];
    for (final c in cinemas) {
      final api = container.read(chainApiProvider(c.chain));
      final r = await checkNavigability(api, c, DateTime.now());
      results.add(r);
      // ignore: avoid_print
      print('${switch (r.verdict) {
        Navigability.navigable => 'OK  ',
        Navigability.programmeOnly => 'PROG',
        Navigability.notNavigable => 'KO  ',
        Navigability.notVerifiableNow => 'WAIT',
      }} ${c.chain.name}:${c.cinemaId} ${c.name} - ${r.reason}');
      await Future<void>.delayed(const Duration(milliseconds: _delayMs));
    }
    File(_report)
      ..createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ')
          .convert([for (final r in results) r.toJson()]));
  }, timeout: const Timeout(Duration(hours: 2)));
}
```

Add under README "## Sviluppo" a short Italian paragraph: what the check is, the command `flutter test --run-skipped --tags live test/live --dart-define=VERIFY_CHAIN=eighteenTickets`, the other `--dart-define`s, and that the report lands in `build/navigability_report.json`.

- [ ] **Step 4: Run** offline tests → PASS; `flutter test` (default) must show the live test as **skipped**, not run; `flutter analyze` → clean.

- [ ] **Step 5: Smoke-run the live check on 3 known-good cinemas** (one per chain family) to prove the runner works end to end:
`flutter test --run-skipped --tags live test/live --dart-define=VERIFY_IDS=609,monopoli,1018 --dart-define=VERIFY_DELAY_MS=3000` (609 = 2Tickets Norba, monopoli = 18tickets RedCarpet, 1018 = The Space Torino). Paste the output in the report. If any of the three is not `OK`/`WAIT`, report it - do not "fix" the cinema.

- [ ] **Step 6: Commit**

```bash
git add test/support/navigability.dart test/core/navigability_test.dart test/live/verify_navigability_test.dart dart_test.yaml README.md
git commit -m "Aggiungi la verifica di navigabilita' dei cinema, basata sul codice dell'app"
```

---

### Task 5: 18tickets discovery script → candidates file

**Files:**
- Create: `tools/discover_eighteentickets_cinemas.py`
- Create: `tools/merge_verified_cinemas.py`
- Test: `test/core/cinema_catalog_test.dart` (append - candidates are not committed, so the test only guards invariants of the merged catalog)

**Interfaces:**
- `discover_eighteentickets_cinemas.py` writes `build/candidates_eighteentickets.json`: a JSON list in catalog-entry shape (`cinemaId`, `name`, `slug`, `address`, `lat`, `lng`, `chain: "eighteenTickets"`, `host`), plus `build/discovery_report.txt` listing duplicates/skips/warnings. It never touches `assets/cinemas.json`.
- `merge_verified_cinemas.py --report build/navigability_report.json --candidates build/candidates_eighteentickets.json [--approve id,id] [--hold id]` appends to `assets/cinemas.json` every candidate whose verdict is `navigable`, plus any `--approve`d ids (programme-only ones get `"hasSeatMap": false`), skipping `--hold` ids; prints what it added and what it left out and why.

- [ ] **Step 1: Write the failing test** (append to `test/core/cinema_catalog_test.dart`, inside `main()`):

```dart
  test('every 18tickets venue has a host and a unique cinemaId', () {
    final e18 = cinemas.where((c) => c.chain == CinemaChain.eighteenTickets);
    expect(e18.every((c) => (c.host ?? '').isNotEmpty), isTrue);
    final hosts = e18.map((c) => c.host).toList();
    expect(hosts.toSet().length, hosts.length);
  });
```

Run it: it should PASS already (guard for the merge to come). That is expected - record it as a guard, not TDD RED.

- [ ] **Step 2: Write `tools/discover_eighteentickets_cinemas.py`**

```python
"""Discovers 18tickets venues missing from assets/cinemas.json.

18tickets has no public venue list (confirmed 13 Oct 2026). Every circuit
gets a wildcard certificate *.CIRCUIT.18tickets.it, so Certificate
Transparency (Cert Spotter API) lists the circuits; each circuit's
/select_cinema?mandatory=true page links its venues (VENUE.CIRCUIT.18tickets.it);
a label with no sub-hosts is a single venue (LABEL.18tickets.it).
A venue homepage gives its name in <title> and its address in the
maps.google.com/?q=ADDRESS link.

Writes build/candidates_eighteentickets.json and build/discovery_report.txt.
Never modifies assets/cinemas.json - candidates must pass the navigability
check first (see README "Sviluppo"). 18tickets answers 429 to bursts: one
request every 3 s, 60 s back-off on 429.
"""
import html
import json
import os
import re
import time
import urllib.parse
import urllib.request
import urllib.error

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")
UA_GEO = ("CinemaDisponibilitaPosti-catalog/1.0 "
          "(github.com/mauronofrio/cinema-disponibilita-posti)")
CATALOG = "assets/cinemas.json"
OUT = "build/candidates_eighteentickets.json"
REPORT = "build/discovery_report.txt"
INFRA = {"www", "demo", "dmo", "staging", "external", "organizzatori", "api"}

report = []


def log(line):
    print(line, flush=True)
    report.append(line)


def get(url, ua=UA, delay=3.0):
    for attempt in range(4):
        req = urllib.request.Request(url, headers={"User-Agent": ua})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                body = r.read().decode("utf-8", "replace")
                time.sleep(delay)
                return r.status, r.geturl(), body
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 3:
                log(f"  429 on {url}, waiting 60 s")
                time.sleep(60)
                continue
            time.sleep(delay)
            return e.code, url, ""
        except Exception as e:  # network error: report, move on
            time.sleep(delay)
            return type(e).__name__, url, ""
    return 429, url, ""


def circuit_labels():
    labels, after = set(), None
    while True:
        url = ("https://api.certspotter.com/v1/issuances?domain=18tickets.it"
               "&include_subdomains=true&expand=dns_names")
        if after:
            url += f"&after={after}"
        _, _, body = get(url, ua=UA_GEO, delay=2.0)
        rows = json.loads(body or "[]")
        if not rows:
            break
        for row in rows:
            for name in row.get("dns_names", []):
                m = re.match(r"^(?:\*\.|api\.)?([a-z0-9-]+)\.18tickets\.it$", name.lower())
                if m and m.group(1) not in INFRA:
                    labels.add(m.group(1))
        after = rows[-1]["id"]
    return sorted(labels)


def venue_hosts(label):
    hosts = set()
    for path in ("/", "/select_cinema?mandatory=true"):
        _, _, body = get(f"https://{label}.18tickets.it{path}")
        hosts |= set(re.findall(r"https?://([a-z0-9-]+\." + re.escape(label) + r"\.18tickets\.it)", body))
        if hosts:
            break
    return sorted(hosts) or [f"{label}.18tickets.it"]


def venue_info(host):
    code, final, body = get(f"https://{host}/")
    if code != 200 or "18tickets.it/" in final and final.rstrip("/").endswith("www.18tickets.it"):
        return None
    title = re.search(r"<title>(.*?)</title>", body, re.S)
    addr = re.search(r"maps\.google\.com/\?q=([^'\"]+)['\"]", body)
    if not title or not addr:
        return None
    return {"name": html.unescape(title.group(1)).strip(),
            "address": html.unescape(urllib.parse.unquote_plus(addr.group(1))).strip()}


def city_of(address):
    # "Via Baione, snc, 70043, Monopoli, BA" -> "Monopoli"
    parts = [p.strip() for p in address.split(",") if p.strip()]
    for p in reversed(parts):
        if not re.fullmatch(r"\d{5}|[A-Z]{2}|snc", p) and not re.search(r"\d", p):
            return p
    return ""


def geocode(address):
    city = city_of(address).casefold()
    q = urllib.parse.urlencode({"q": address, "format": "json", "limit": 5, "addressdetails": 1})
    _, _, body = get(f"https://nominatim.openstreetmap.org/search?{q}", ua=UA_GEO, delay=1.1)
    for hit in json.loads(body or "[]"):
        a = hit.get("address", {})
        names = {str(a.get(k, "")).casefold() for k in ("city", "town", "village", "municipality")}
        if city and city in names:
            return float(hit["lat"]), float(hit["lon"])
    return None


def main():
    os.makedirs("build", exist_ok=True)
    catalog = json.load(open(CATALOG, encoding="utf-8"))
    known_hosts = {c.get("host") for c in catalog if c.get("chain") == "eighteenTickets"}
    known_ids = {c["cinemaId"] for c in catalog}
    candidates = []
    for label in circuit_labels():
        for host in venue_hosts(label):
            if host in known_hosts:
                continue
            info = venue_info(host)
            if info is None:
                log(f"skip {host}: no name/address on homepage (not a venue page)")
                continue
            coords = geocode(info["address"])
            if coords is None:
                log(f"NOT GEOCODED {host}: {info['name']} - {info['address']}")
                continue
            # Review Focus 5: same building already in the catalog (any chain,
            # e.g. a custom-domain 18tickets site) -> duplicate, not a candidate.
            near = [c for c in catalog
                    if abs(c["lat"] - coords[0]) < 0.0015 and abs(c["lng"] - coords[1]) < 0.002]
            if near:
                log(f"POSSIBLE DUPLICATE {host} ({info['name']}) ~ "
                    + ", ".join(f"{c['name']} [{c.get('chain')}:{c['cinemaId']}]" for c in near))
                continue
            sub, circuit = (host.split(".")[0], host.split(".")[1]) if host.count(".") > 2 else (host.split(".")[0], "")
            cid = f"{sub}-{circuit}" if circuit else sub
            while cid in known_ids:
                cid += "-2"
            known_ids.add(cid)
            candidates.append({"cinemaId": cid, "name": f"{info['name']} - {city_of(info['address'])}",
                               "slug": cid, "address": info["address"], "lat": coords[0],
                               "lng": coords[1], "chain": "eighteenTickets", "host": host})
            log(f"candidate {cid}: {info['name']} - {info['address']}")
    json.dump(candidates, open(OUT, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=2)
    open(REPORT, "w", encoding="utf-8", newline="\n").write("\n".join(report) + "\n")
    print(f"{len(candidates)} candidates -> {OUT}")


if __name__ == "__main__":
    main()
```

(Verify `city_of` against the RedCarpet address "Via Baione, snc, 70043, Monopoli, BA" → "Monopoli" with a quick `python -c` before the real run; adjust if the real address formats differ and note it.)

- [ ] **Step 3: Write `tools/merge_verified_cinemas.py`**

```python
"""Appends verified candidates to assets/cinemas.json (never reorders or
reformats existing entries). Usage:
  python tools/merge_verified_cinemas.py --report build/navigability_report.json \
      --candidates build/candidates_eighteentickets.json [--approve a,b] [--hold c]
navigable -> added; programmeOnly + --approve -> added with hasSeatMap false;
--hold -> left out on purpose (e.g. kept back to test the remote update)."""
import argparse
import json

p = argparse.ArgumentParser()
p.add_argument("--report", required=True)
p.add_argument("--candidates", required=True)
p.add_argument("--approve", default="")
p.add_argument("--hold", default="")
a = p.parse_args()
approve = {x for x in a.approve.split(",") if x}
hold = {x for x in a.hold.split(",") if x}
verdicts = {r["cinemaId"]: r for r in json.load(open(a.report, encoding="utf-8"))}
catalog = json.load(open("assets/cinemas.json", encoding="utf-8"))
keys = {(c.get("chain") or "theSpace", c["cinemaId"]) for c in catalog}
for cand in json.load(open(a.candidates, encoding="utf-8")):
    cid, v = cand["cinemaId"], verdicts.get(cand["cinemaId"], {})
    verdict = v.get("verdict", "unchecked")
    if cid in hold:
        print(f"HELD   {cid} ({verdict})"); continue
    if (cand["chain"], cid) in keys:
        print(f"EXISTS {cid}"); continue
    if verdict == "navigable" or (verdict == "programmeOnly" and cid in approve):
        if verdict == "programmeOnly":
            cand["hasSeatMap"] = False
        catalog.append(cand); keys.add((cand["chain"], cid))
        print(f"ADDED  {cid} ({verdict})")
    else:
        print(f"LEFT   {cid} ({verdict}: {v.get('reason', '')})")
open("assets/cinemas.json", "w", encoding="utf-8", newline="\n").write(
    json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
```

- [ ] **Step 4: Run** `flutter analyze` and `flutter test` → green (scripts are not exercised by the suite; the guard test passes).

- [ ] **Step 5: Commit**

```bash
git add tools/discover_eighteentickets_cinemas.py tools/merge_verified_cinemas.py test/core/cinema_catalog_test.dart
git commit -m "Aggiungi gli script di scoperta e di inserimento verificato dei cinema 18tickets"
```

---

### Task 6: Run discovery + verification, triage with the user (controller + user)

Not a subagent coding task: the controller runs it, because it needs the user's decisions.

- [ ] **Step 1:** `PYTHONIOENCODING=utf-8 python tools/discover_eighteentickets_cinemas.py` (background, long - tens of minutes at 3 s/request). Read `build/discovery_report.txt`.
- [ ] **Step 2:** `flutter test --run-skipped --tags live test/live --dart-define=VERIFY_FILE=build/candidates_eighteentickets.json --dart-define=VERIFY_DELAY_MS=8000` (8 s between cinemas: each check is 3-4 requests on 18tickets).
- [ ] **Step 3:** Present the user a triage table: ✅ navigable (to add) · ⚠️ programme only (user decides) · ❌ not navigable, grouped by reason (these are the "special cinemas" - each reason that looks like a parser gap becomes an item for a follow-up plan *before the release*) · ⏳ not verifiable now · flagged names (Teatro/Festival/Arena/Svizzera) for a keep/drop decision · possible duplicates.
- [ ] **Step 4:** With the user's answers, pick **one** ✅ cinema (ideally one near the user, in Puglia) to **hold back** for the post-release remote-update test. Then:
  `python tools/merge_verified_cinemas.py --report build/navigability_report.json --candidates build/candidates_eighteentickets.json --approve <ids> --hold <held id>`
  then `PYTHONIOENCODING=utf-8 python tools/update_readme_counts.py`, update the README 18tickets row with the new cities, `flutter analyze`, `flutter test`, commit: `"Aggiungi al catalogo i cinema 18tickets verificati"`.
- [ ] **Step 5:** Save the held-back entry (full JSON) to `docs/superpowers/plans/2026-10-13-held-back-cinema.json` and commit it with the plan, so the post-release test (append it to `assets/cinemas.json` + update README counts + push; within 24 h the installed 1.0.8 shows it without an update) has everything it needs.

## Post-release check (after 1.0.8 is published and installed)

Append the held-back entry, run `tools/update_readme_counts.py`, test, commit, push. On the phone: the cinema appears in the picker within a day (or at once after clearing app data), opens, shows programme and seat map. Then repeat with a fake entry `"minAppVersion": "9.9.9"` pushed and reverted, to confirm it stays hidden.
