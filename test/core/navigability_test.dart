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
  _Api({
    this.dates,
    this.sessions = const [],
    this.seatMap,
    this.datesError,
    this.filmsError,
    this.seatError,
    this.failures = 999,
    this.failingSessions,
  });
  final List<ShowingDate>? dates;
  final List<Session> sessions;
  final SeatMap? seatMap;
  final Object? datesError;
  final Object? filmsError;
  final Object? seatError;

  /// How many calls of each kind fail before one succeeds.
  final int failures;

  /// If set, only these session ids fail seat-map loading (always).
  final Set<String>? failingSessions;
  final Map<String, int> calls = {};
  final List<String> seatRequests = [];

  bool _fails(String key) => (calls[key] = (calls[key] ?? 0) + 1) <= failures;

  @override
  Future<List<ShowingDate>> getShowingDates(Cinema c) async {
    if (datesError != null && _fails('dates')) throw datesError!;
    return dates ?? [ShowingDate(date: DateTime(2026, 10, 20), hasShowings: true)];
  }

  @override
  Future<List<Film>> getFilmsForDay(Cinema c, DateTime day) async {
    if (filmsError != null && _fails('films')) throw filmsError!;
    return [
      Film(filmId: 'f', title: 'F', posterImageSrc: null, runningTime: 100,
          showingGroups: [ShowingGroup(date: DateTime(2026, 10, 20), sessions: sessions)]),
    ];
  }

  @override
  Future<SeatMap> getSeatMap(Cinema c, Session s) async {
    seatRequests.add(s.sessionId);
    if (failingSessions != null) {
      if (failingSessions!.contains(s.sessionId)) throw Exception('seat');
    } else if (seatError != null && _fails('seat')) {
      throw seatError!;
    }
    return seatMap ?? _seats(10);
  }
}

Future<NavigabilityResult> _check(_Api api, [Cinema cinema = _cinema]) =>
    checkNavigability(api, cinema, _now, pause: (_) async {});

const _cinema = Cinema(cinemaId: 'c', name: 'C', slug: 'c', address: 'a',
    lat: 41, lng: 16, chain: CinemaChain.eighteenTickets);

void main() {
  test('dates, a future session, seats and a booking link: navigable', () async {
    final r = await _check(_Api(sessions: [_session(_now.add(const Duration(hours: 2)))]));
    expect(r.verdict, Navigability.navigable);
  });

  test('the programme fails to load: not navigable', () async {
    final r = await _check(_Api(datesError: Exception('boom')));
    expect(r.verdict, Navigability.notNavigable);
  });

  test('Review Focus 4: dates but no future session (end of the day, '
      'season over) is "not verifiable now" - never navigable, never broken', () async {
    final r = await _check(_Api(sessions: [_session(_now.subtract(const Duration(hours: 3)))]));
    expect(r.verdict, Navigability.notVerifiableNow);
    final none = await _check(_Api(dates: const []));
    expect(none.verdict, Navigability.notVerifiableNow);
  });

  test('seat map fails or is empty: programme only', () async {
    final s = [_session(_now.add(const Duration(hours: 2)))];
    expect((await _check(_Api(sessions: s, seatError: Exception('x')))).verdict,
        Navigability.programmeOnly);
    expect((await _check(_Api(sessions: s, seatMap: _seats(0)))).verdict,
        Navigability.programmeOnly);
  });

  test('no booking link: programme only', () async {
    final r = await _check(_Api(sessions: [_session(_now.add(const Duration(hours: 2)), booking: null)]));
    expect(r.verdict, Navigability.programmeOnly);
  });

  test('a transient seat-map failure is retried once: navigable', () async {
    final api = _Api(sessions: [_session(_now.add(const Duration(hours: 2)))],
        seatError: Exception('429'), failures: 1);
    expect((await _check(api)).verdict, Navigability.navigable);
    expect(api.seatRequests.length, 2);
  });

  test('first session fails twice, the second works: navigable', () async {
    final first = _session(_now.add(const Duration(hours: 2)));
    final second = _session(_now.add(const Duration(hours: 4)));
    final api = _Api(sessions: [second, first], failingSessions: {first.sessionId});
    expect((await _check(api)).verdict, Navigability.navigable);
    expect(api.seatRequests, [first.sessionId, first.sessionId, second.sessionId]);
  });

  test('seat map always fails on both sessions: programme only', () async {
    final api = _Api(sessions: [
      _session(_now.add(const Duration(hours: 2))),
      _session(_now.add(const Duration(hours: 4))),
    ], seatError: Exception('x'));
    expect((await _check(api)).verdict, Navigability.programmeOnly);
  });

  test('the retry waits retryDelay through the injected pause', () async {
    final waits = <Duration>[];
    final api = _Api(sessions: [_session(_now.add(const Duration(hours: 2)))],
        seatError: Exception('x'), failures: 1);
    await checkNavigability(api, _cinema, _now, pause: (d) async => waits.add(d));
    expect(waits, [const Duration(seconds: 10)]);
  });

  test('transient dates failure is retried once; persistent one is not navigable', () async {
    final s = [_session(_now.add(const Duration(hours: 2)))];
    expect((await _check(_Api(sessions: s, datesError: Exception('x'), failures: 1))).verdict,
        Navigability.navigable);
    expect((await _check(_Api(sessions: s, datesError: Exception('x')))).verdict,
        Navigability.notNavigable);
  });

  test('getFilmsForDay: transient retried, persistent failure not navigable', () async {
    final s = [_session(_now.add(const Duration(hours: 2)))];
    expect((await _check(_Api(sessions: s, filmsError: Exception('x'), failures: 1))).verdict,
        Navigability.navigable);
    expect((await _check(_Api(sessions: s, filmsError: Exception('x')))).verdict,
        Navigability.notNavigable);
  });

  test('hasSeatMap false: programme only, or not verifiable if nothing scheduled', () async {
    const noMap = Cinema(cinemaId: 'c', name: 'C', slug: 'c', address: 'a',
        lat: 41, lng: 16, chain: CinemaChain.eighteenTickets, hasSeatMap: false);
    final s = [_session(_now.add(const Duration(hours: 2)))];
    expect((await _check(_Api(sessions: s), noMap)).verdict, Navigability.programmeOnly);
    expect((await _check(_Api(dates: const []), noMap)).verdict, Navigability.notVerifiableNow);
  });

  test('dates outside the window or without showings are ignored', () async {
    final s = [_session(_now.add(const Duration(hours: 2)))];
    final api = _Api(sessions: s, dates: [
      ShowingDate(date: DateTime(2026, 10, 19), hasShowings: true), // yesterday
      ShowingDate(date: DateTime(2026, 10, 27), hasShowings: true), // day +7
      ShowingDate(date: DateTime(2026, 10, 21), hasShowings: false),
    ]);
    expect((await _check(api)).verdict, Navigability.notVerifiableNow);
    final inside = _Api(sessions: s, dates: [
      ShowingDate(date: DateTime(2026, 10, 19), hasShowings: true),
      ShowingDate(date: DateTime(2026, 10, 20), hasShowings: true), // today
    ]);
    expect((await _check(inside)).verdict, Navigability.navigable);
  });

  test('mixed past and future sessions: the earliest future one is used', () async {
    final past = _session(_now.subtract(const Duration(hours: 3)));
    final soon = _session(_now.add(const Duration(hours: 1)));
    final late = _session(_now.add(const Duration(hours: 5)));
    final api = _Api(sessions: [late, past, soon]);
    expect((await _check(api)).verdict, Navigability.navigable);
    expect(api.seatRequests, [soon.sessionId]);
  });

  test('a seat map with only unnumbered sectors counts as seats', () async {
    final map = SeatMap(
      screenLabel: '', totalRows: 0, totalColumns: 0, rows: const [],
      areaCategories: const [],
      unnumberedSectors: const [
        UnnumberedSector(name: 'Platea', freeSeats: 50, capacity: 100),
      ],
    );
    final api = _Api(sessions: [_session(_now.add(const Duration(hours: 2)))], seatMap: map);
    expect((await _check(api)).verdict, Navigability.navigable);
  });
}
