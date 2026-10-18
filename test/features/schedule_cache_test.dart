import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thespace_companion/core/chains/chain_api.dart';
import 'package:thespace_companion/core/chains/chain_registry.dart';
import 'package:thespace_companion/core/date/clock.dart';
import 'package:thespace_companion/core/models/cinema.dart';
import 'package:thespace_companion/core/models/film.dart';
import 'package:thespace_companion/core/models/seat_map.dart';
import 'package:thespace_companion/core/models/showing_date.dart';
import 'package:thespace_companion/core/storage/schedule_cache_store.dart';
import 'package:thespace_companion/features/showtimes/films_provider.dart';
import 'package:thespace_companion/features/showtimes/showing_dates_provider.dart';

class _MutableClock extends Clock {
  _MutableClock(this.current);
  DateTime current;
  @override
  DateTime now() => current;
}

/// Counts every call: each one stands for a request to the cinema.
class _CountingChainApi implements ChainApi {
  int filmCalls = 0;
  int dateCalls = 0;

  @override
  Future<List<Film>> getFilmsForDay(Cinema cinema, DateTime day) async {
    filmCalls++;
    // Like The Space/UCI: every day at once, whatever day is asked.
    return [_film(DateTime(2026, 10, 20)), _film(DateTime(2026, 10, 21))];
  }

  @override
  Future<List<ShowingDate>> getShowingDates(Cinema cinema) async {
    dateCalls++;
    return [ShowingDate(date: DateTime(2026, 10, 20), hasShowings: true)];
  }

  @override
  Future<SeatMap> getSeatMap(Cinema cinema, Session session) =>
      throw UnimplementedError();
}

Film _film(DateTime day) => Film(
  filmId: 'f${day.day}',
  title: 'Film ${day.day}',
  posterImageSrc: 'https://example.com/p.jpg',
  runningTime: 120,
  showingGroups: [
    ShowingGroup(
      date: day,
      sessions: [
        Session(
          sessionId: 's${day.day}',
          startTime: DateTime(day.year, day.month, day.day, 21),
          endTime: DateTime(day.year, day.month, day.day, 23),
          screenName: 'Sala 1',
          isSoldOut: true,
          formattedPrice: '8,00 €',
          isPriceVisible: true,
          attributes: const [
            SessionAttribute(
              name: 'ITA',
              attributeType: 'Language',
              color: null,
            ),
          ],
          bookingPath: 'https://example.com/buy/1',
          webticScreenId: 7,
          eighteenTicketsFilmId: '42',
          twoTicketsServerEse: 'pf2.example.it',
          twoTicketsPortEse: '80',
        ),
      ],
    ),
  ],
);

const _cinema = Cinema(
  cinemaId: 'c1',
  name: 'C',
  slug: 'c',
  address: 'Via C 1',
  lat: 0,
  lng: 0,
  chain: CinemaChain.uci,
);

final _today = DateTime(2026, 10, 20);
final _tomorrow = DateTime(2026, 10, 21);

void main() {
  late _MutableClock clock;
  late _CountingChainApi api;

  /// A fresh container is a fresh app process: nothing in memory, only what
  /// was saved on the device survives.
  ProviderContainer launch() {
    final c = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(clock),
        chainApiProvider.overrideWith((ref, chain) => api),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = _MutableClock(DateTime(2026, 10, 20, 12));
    api = _CountingChainApi();
  });

  test('today downloaded after 11: not downloaded again on relaunch', () async {
    await launch().read(filmsForDayProvider((_cinema, _today)).future);
    clock.current = DateTime(2026, 10, 20, 22);
    final films = await launch().read(
      filmsForDayProvider((_cinema, _today)).future,
    );
    expect(api.filmCalls, 1);
    expect(films.map((f) => f.filmId), ['f20']);
  });

  test(
    'today downloaded before 11: reused until 11, downloaded after',
    () async {
      clock.current = DateTime(2026, 10, 20, 9);
      await launch().read(filmsForDayProvider((_cinema, _today)).future);
      clock.current = DateTime(2026, 10, 20, 10, 30);
      await launch().read(filmsForDayProvider((_cinema, _today)).future);
      expect(api.filmCalls, 1);
      clock.current = DateTime(2026, 10, 20, 11, 5);
      await launch().read(filmsForDayProvider((_cinema, _today)).future);
      expect(api.filmCalls, 2);
      clock.current = DateTime(2026, 10, 20, 18);
      await launch().read(filmsForDayProvider((_cinema, _today)).future);
      expect(api.filmCalls, 2);
    },
  );

  test('tomorrow seen today: reused until 11 of tomorrow', () async {
    await launch().read(filmsForDayProvider((_cinema, _tomorrow)).future);
    clock.current = DateTime(2026, 10, 21, 10);
    await launch().read(filmsForDayProvider((_cinema, _tomorrow)).future);
    expect(api.filmCalls, 1);
    clock.current = DateTime(2026, 10, 21, 11, 30);
    await launch().read(filmsForDayProvider((_cinema, _tomorrow)).future);
    expect(api.filmCalls, 2);
  });

  test('the saved copy keeps every field the app uses', () async {
    await launch().read(filmsForDayProvider((_cinema, _today)).future);
    final film = (await launch().read(
      filmsForDayProvider((_cinema, _today)).future,
    )).single;
    final s = film.sessionsOn(_today).single;
    expect(api.filmCalls, 1);
    expect(
      (film.title, film.posterImageSrc, film.runningTime),
      ('Film 20', 'https://example.com/p.jpg', 120),
    );
    expect(
      (s.sessionId, s.startTime, s.endTime, s.screenName),
      ('s20', DateTime(2026, 10, 20, 21), DateTime(2026, 10, 20, 23), 'Sala 1'),
    );
    expect(
      (s.isSoldOut, s.formattedPrice, s.isPriceVisible, s.bookingPath),
      (true, '8,00 €', true, 'https://example.com/buy/1'),
    );
    expect(
      (
        s.webticScreenId,
        s.eighteenTicketsFilmId,
        s.twoTicketsServerEse,
        s.twoTicketsPortEse,
      ),
      (7, '42', 'pf2.example.it', '80'),
    );
    expect(
      (s.attributes.single.name, s.attributes.single.attributeType),
      ('ITA', 'Language'),
    );
  });

  test('pull-to-refresh (forget) always downloads again', () async {
    final app = launch();
    await app.read(filmsForDayProvider((_cinema, _today)).future);
    await app.read(showingDatesProvider(_cinema).future);
    await app.read(scheduleCacheStoreProvider).forget(_cinema, day: _today);
    app.invalidate(filmsForDayProvider((_cinema, _today)));
    app.invalidate(showingDatesProvider(_cinema));
    await app.read(filmsForDayProvider((_cinema, _today)).future);
    await app.read(showingDatesProvider(_cinema).future);
    expect((api.filmCalls, api.dateCalls), (2, 2));
  });

  test('a corrupted saved entry is just downloaded again', () async {
    SharedPreferences.setMockInitialValues({
      'schedule_v1|films|uci|c1|2026-10-20': '{"fetchedAt": "nope", "data": 3}',
    });
    final films = await launch().read(
      filmsForDayProvider((_cinema, _today)).future,
    );
    expect(api.filmCalls, 1);
    expect(films, isNotEmpty);
  });

  test('list of days: reused today, downloaded again the next day', () async {
    await launch().read(showingDatesProvider(_cinema).future);
    clock.current = DateTime(2026, 10, 20, 23);
    await launch().read(showingDatesProvider(_cinema).future);
    expect(api.dateCalls, 1);
    clock.current = DateTime(2026, 10, 21, 8);
    await launch().read(showingDatesProvider(_cinema).future);
    expect(api.dateCalls, 2);
  });

  test(
    'purgeBefore drops past days and old lists of days, keeps the rest',
    () async {
      final store = ScheduleCacheStore();
      final films = await api.getFilmsForDay(_cinema, _today);
      await store.writeFilms(
        _cinema,
        DateTime(2026, 10, 19),
        films,
        DateTime(2026, 10, 19, 12),
      );
      await store.writeFilms(
        _cinema,
        _today,
        films,
        DateTime(2026, 10, 19, 12),
      );
      await store.writeShowingDates(
        _cinema,
        const [],
        DateTime(2026, 10, 19, 12),
      );
      await store.purgeBefore(DateTime(2026, 10, 20, 8));
      final keys = (await SharedPreferences.getInstance()).getKeys();
      expect(keys, {'schedule_v1|films|uci|c1|2026-10-20'});
    },
  );
}
