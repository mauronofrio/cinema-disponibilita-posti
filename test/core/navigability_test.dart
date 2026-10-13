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
