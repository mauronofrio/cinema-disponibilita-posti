import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/chains/two_tickets_chain_api.dart';
import 'package:thespace_companion/core/date/clock.dart';
import 'package:thespace_companion/core/models/cinema.dart';
import 'package:thespace_companion/core/models/film.dart';
import 'package:thespace_companion/core/network/api_client.dart'
    show ApiException;
import 'package:thespace_companion/core/network/two_tickets_api_client.dart';

class _FixedClock extends Clock {
  const _FixedClock();
  @override
  DateTime now() => DateTime(2026, 10, 13, 12);
}

/// Serves the captured fixtures instead of the network and counts calls.
class _FakeClient extends TwoTicketsApiClient {
  _FakeClient({this.venueHtml, this.failFilmIds = const {}}) : super(Dio());

  final String? venueHtml;

  /// Film ids whose checkout page request fails.
  final Set<String> failFilmIds;
  int venueCalls = 0;
  int checkoutCalls = 0;
  int sectorCalls = 0;

  String fx(String n) => File('test/fixtures/twotickets_$n').readAsStringSync();

  @override
  Future<String> getVenuePage(String venueId) async {
    venueCalls++;
    return venueHtml ?? fx('venue_609.html');
  }

  @override
  Future<String> getCheckoutPage(String filmId, String venueId) async {
    checkoutCalls++;
    if (failFilmIds.contains(filmId)) throw Exception('boom $filmId');
    return fx('checkout_22259_609.html');
  }

  @override
  Future<String> getSectors({
    required String eventId,
    required String time,
    required String serverEse,
    required String portEse,
  }) async {
    sectorCalls++;
    return fx('settori_single.json');
  }

  @override
  Future<String> getSeats({
    required int sectorId,
    required String eventId,
    required String rawTime,
    required String serverEse,
    required String portEse,
  }) async => fx('posti_empty.json');
}

const _norba = Cinema(
  cinemaId: '609',
  name: 'Cine Teatro Norba',
  slug: '609',
  address: 'Piazza della Repubblica, 29 Conversano (BA)',
  lat: 40.97,
  lng: 17.11,
  chain: CinemaChain.twoTickets,
);

void main() {
  test('CinemaChain round-trips "twoTickets" from the catalog json', () {
    expect(CinemaChain.fromJson('twoTickets'), CinemaChain.twoTickets);
  });

  test('programme: one film per cinema title, sessions per date, booking '
      'link and ticketing server carried on each session', () async {
    final client = _FakeClient();
    final api = TwoTicketsChainApi(client, const _FixedClock());
    final films = await api.getFilmsForDay(_norba, DateTime(2026, 10, 13));

    expect(films, hasLength(6));
    final estranea = films.firstWhere((f) => f.filmId == '22259');
    expect(estranea.title, "L'ESTRANEA");
    final today = estranea.sessionsOn(DateTime(2026, 10, 13));
    expect(today.map((s) => s.sessionId), ['610899', '610900', '610951']);
    final s = today.first;
    expect(s.screenName, 'N1');
    expect(s.endTime, s.startTime.add(const Duration(minutes: 110)));
    expect(s.isSoldOut, isFalse);
    expect(s.twoTicketsServerEse, 'pf2.twoitalia.it');
    expect(
      s.bookingPath,
      'https://www.2tickets.it/biglietto/Acquisto/Checkout/22259/609/610899'
      '?settore=C&orario=17.30',
    );
  });

  test('showing dates come from the same cached programme - no second '
      'round of page loads', () async {
    final client = _FakeClient();
    final api = TwoTicketsChainApi(client, const _FixedClock());
    await api.getFilmsForDay(_norba, DateTime(2026, 10, 13));
    final dates = await api.getShowingDates(_norba);

    expect(dates.map((d) => d.date), [
      DateTime(2026, 10, 13),
      DateTime(2026, 10, 14),
    ]);
    expect(client.venueCalls, 1);
    expect(client.checkoutCalls, 6);
  });

  test('Review Focus 1: a venue with only theatre right now is an empty '
      'programme, not an error', () async {
    final theatreOnly = File('test/fixtures/twotickets_venue_609.html')
        .readAsStringSync()
        .replaceAll('?settore=C', '?settore=T');
    final api = TwoTicketsChainApi(
      _FakeClient(venueHtml: theatreOnly),
      const _FixedClock(),
    );
    expect(await api.getFilmsForDay(_norba, DateTime(2026, 10, 13)), isEmpty);
    expect(await api.getShowingDates(_norba), isEmpty);
  });

  test('seat map for a session from the programme', () async {
    final api = TwoTicketsChainApi(_FakeClient(), const _FixedClock());
    final films = await api.getFilmsForDay(_norba, DateTime(2026, 10, 13));
    final session = films
        .firstWhere((f) => f.filmId == '22259')
        .sessionsOn(DateTime(2026, 10, 14))
        .last; // 610952, 21.30, N3
    final map = await api.getSeatMap(_norba, session);
    expect(map.availableSeatCount, 70);
    expect(map.rows, hasLength(8));
  });

  test('getSeatMap: an empty ticketing server (config absent on the page) is '
      '"missing" - fails before any request', () async {
    final client = _FakeClient();
    final api = TwoTicketsChainApi(client, const _FixedClock());
    final films = await api.getFilmsForDay(_norba, DateTime(2026, 10, 13));
    final s = films.first.showingGroups.first.sessions.first;
    final broken = Session(
      sessionId: s.sessionId,
      startTime: s.startTime,
      endTime: s.endTime,
      screenName: s.screenName,
      isSoldOut: false,
      formattedPrice: null,
      isPriceVisible: false,
      attributes: const [],
      bookingPath: null,
      twoTicketsServerEse: '',
      twoTicketsPortEse: '80',
    );
    await expectLater(
      api.getSeatMap(_norba, broken),
      throwsA(isA<ApiException>()),
    );
    expect(client.sectorCalls, 0);
  });

  test('one failed checkout page drops only that film', () async {
    final client = _FakeClient(failFilmIds: {'22259'});
    final api = TwoTicketsChainApi(client, const _FixedClock());
    final films = await api.getFilmsForDay(_norba, DateTime(2026, 10, 13));
    expect(films, hasLength(5));
    expect(films.any((f) => f.filmId == '22259'), isFalse);
  });

  test('every checkout page failing fails the programme, uncached', () async {
    final all = RegExp(r'Checkout/(\d+)/609\?settore=C')
        .allMatches(
          File('test/fixtures/twotickets_venue_609.html').readAsStringSync(),
        )
        .map((m) => m.group(1)!)
        .toSet();
    final client = _FakeClient(failFilmIds: all);
    final api = TwoTicketsChainApi(client, const _FixedClock());
    await expectLater(
      api.getFilmsForDay(_norba, DateTime(2026, 10, 13)),
      throwsA(anything),
    );
    final before = client.venueCalls;
    await expectLater(
      api.getFilmsForDay(_norba, DateTime(2026, 10, 13)),
      throwsA(anything),
    );
    expect(client.venueCalls, before + 1, reason: 'refetched, not cached');
  });
}
