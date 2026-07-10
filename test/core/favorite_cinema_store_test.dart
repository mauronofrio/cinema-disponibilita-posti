import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thespace_companion/core/models/cinema.dart';
import 'package:thespace_companion/core/storage/favorite_cinema_store.dart';

Cinema _cinema(String cinemaId, CinemaChain chain) => Cinema(
  cinemaId: cinemaId,
  name: '$chain/$cinemaId',
  slug: cinemaId,
  address: 'Via Test 1',
  lat: 0,
  lng: 0,
  chain: chain,
);

void main() {
  setUp(() {
    // Fresh, empty prefs for every test - this is the plugin's documented
    // in-memory test backend, no real platform channel involved.
    SharedPreferences.setMockInitialValues({});
  });

  group('FavoriteCinemaStore', () {
    test('addAndActivate persists the cinema as both favorite and active', () async {
      final store = FavoriteCinemaStore();
      final cinema = _cinema('42', CinemaChain.theSpace);

      await store.addAndActivate(cinema);

      expect(await store.readFavorites(), [FavoriteCinemaStore.keyFor(cinema)]);
      expect(await store.readActive(), FavoriteCinemaStore.keyFor(cinema));
    });

    test(
      'the same cinemaId on two different chains resolves to two independent favorites',
      () async {
        // This is the exact bug class being fixed: cinema ids are only
        // unique within their own chain (see Cinema.==), so persisting by
        // bare cinemaId would collapse these into a single favorite.
        final store = FavoriteCinemaStore();
        final theSpaceCinema = _cinema('42', CinemaChain.theSpace);
        final uciCinema = _cinema('42', CinemaChain.uci);

        await store.addAndActivate(theSpaceCinema);
        await store.addAndActivate(uciCinema);

        final favorites = await store.readFavorites();
        expect(favorites, hasLength(2));
        expect(favorites, contains(FavoriteCinemaStore.keyFor(theSpaceCinema)));
        expect(favorites, contains(FavoriteCinemaStore.keyFor(uciCinema)));

        // Activating one must not affect or be confused with the other.
        await store.setActive(theSpaceCinema);
        expect(await store.readActive(), FavoriteCinemaStore.keyFor(theSpaceCinema));

        await store.setActive(uciCinema);
        expect(await store.readActive(), FavoriteCinemaStore.keyFor(uciCinema));

        // Removing one leaves the other favorite untouched.
        await store.remove(theSpaceCinema);
        final remaining = await store.readFavorites();
        expect(remaining, [FavoriteCinemaStore.keyFor(uciCinema)]);
      },
    );

    test(
      'removing the active favorite promotes the first remaining one to active',
      () async {
        final store = FavoriteCinemaStore();
        final first = _cinema('1', CinemaChain.theSpace);
        final second = _cinema('2', CinemaChain.theSpace);

        await store.addAndActivate(first);
        await store.addAndActivate(second);
        await store.setActive(first);

        await store.remove(first);

        expect(await store.readActive(), FavoriteCinemaStore.keyFor(second));
      },
    );

    test('removing the last favorite clears the active cinema entirely', () async {
      final store = FavoriteCinemaStore();
      final cinema = _cinema('1', CinemaChain.theSpace);

      await store.addAndActivate(cinema);
      await store.remove(cinema);

      expect(await store.readFavorites(), isEmpty);
      expect(await store.readActive(), isNull);
    });

    test(
      'keyFor namespaces by chain so equal cinemaIds across chains never collide',
      () {
        final theSpaceCinema = _cinema('7', CinemaChain.theSpace);
        final uciCinema = _cinema('7', CinemaChain.uci);

        expect(
          FavoriteCinemaStore.keyFor(theSpaceCinema),
          isNot(FavoriteCinemaStore.keyFor(uciCinema)),
        );
      },
    );
  });
}
