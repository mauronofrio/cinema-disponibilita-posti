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

    test(
      'this is what makes a composite "title|language" cache key safe: two '
      'different keys that happen to share a title prefix are fully '
      'independent, never conflated',
      () async {
        final store = FilmInfoStore();
        await store.write(
          'Oceania|it-IT',
          FilmInfo(
            overview: 'Italiano',
            trailerUrl: null,
            fetchedAt: DateTime(2026, 8, 24),
          ),
        );

        expect(await store.read('Oceania|en-US'), isNull);
        expect((await store.read('Oceania|it-IT'))!.overview, 'Italiano');
      },
    );

    test(
      'a corrupted cache (unparseable JSON) degrades to empty instead of '
      'throwing on every subsequent read',
      () async {
        SharedPreferences.setMockInitialValues({
          'film_info_cache': 'not valid json',
        });
        final store = FilmInfoStore();

        expect(await store.read('Oceania'), isNull);
      },
    );
  });
}
