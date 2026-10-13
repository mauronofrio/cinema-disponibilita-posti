import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/chains/two_tickets/two_tickets_checkout_parser.dart';
import 'package:thespace_companion/core/chains/two_tickets/two_tickets_seat_map_parser.dart';
import 'package:thespace_companion/core/chains/two_tickets/two_tickets_venue_parser.dart';
import 'package:thespace_companion/core/models/seat_map.dart';

void main() {
  group('parseTwoTicketsVenuePage', () {
    late TwoTicketsVenuePage page;
    setUpAll(() {
      page = parseTwoTicketsVenuePage(
        File('test/fixtures/twotickets_venue_609.html').readAsStringSync(),
      );
    });

    test('venue name and address come from the header', () {
      expect(page.name, 'Cine Teatro Norba');
      expect(page.address, 'Piazza della Repubblica, 29 CONVERSANO (BA)');
    });

    test('this is the actual feature requirement: only cinema titles - the '
        '8 theatre plays the same venue sells (settore=T, "TEATRO PROSA") '
        'never reach the app', () {
      expect(page.films.map((f) => f.filmId), [
        '22259', '21315', '22192', '22490', '22530', '21368',
      ]);
      expect(page.films.any((f) => f.title == 'BASTA POCO'), isFalse);
    });

    test('titles: entities decoded, doubled apostrophes collapsed, trimmed', () {
      expect(page.films.first.title, "L'ESTRANEA");
      expect(page.films[3].title, "LA CITTA' DEI VIVI");
      expect(cleanTwoTicketsTitle('INFERNO ITALIA '), 'INFERNO ITALIA');
    });

    test('running time and poster', () {
      expect(page.films.first.runningTime, 110);
      expect(
        page.films.first.posterUrl,
        'https://www.2tickets.it/img/locandine/cinetel-22259.jpg',
      );
    });

    test('the locandina_null placeholder means "no poster"', () {
      const card = '''
<div class="cinema-header"><h1>X</h1><p>Via Y 1  CITTA (XX)</p></div>
<div class="titolo-card" onclick="window.location.href='/biglietto/Acquisto/Checkout/1/2?settore=C'">
<img src="https://www.2tickets.it/img/locandine/locandina_null_2.jpg" alt="T">
<h3 class="titolo-title">T</h3>
<span><i class="bi bi-tag-fill"></i> CINEMA</span> <span><i class="bi bi-clock-fill"></i> 90 min</span>
<div class="btn-fasticket-container"></div></div>''';
      expect(parseTwoTicketsVenuePage(card).films.single.posterUrl, isNull);
    });
  });

  group('parseTwoTicketsCheckoutPage', () {
    late TwoTicketsCheckoutPage page;
    setUpAll(() {
      page = parseTwoTicketsCheckoutPage(
        File('test/fixtures/twotickets_checkout_22259_609.html')
            .readAsStringSync(),
      );
    });

    test('every performance in orariServer, every date at once', () {
      expect(page.performances.map((p) => p.eventId), [
        '610899', '610900', '610951', '610901', '610902', '610952',
      ]);
      final first = page.performances.first;
      expect(first.startTime, DateTime(2026, 10, 13, 17, 30));
      expect(first.hall, 'N1');
      expect(first.freeSeats, 373);
      expect(first.rawTime, '17.30');
      expect(first.isOriginalLanguage, isFalse);
    });

    test('ticketing server comes from the page config', () {
      expect(page.serverEse, 'pf2.twoitalia.it');
      expect(page.portEse, '80');
    });

    String push(int free, {bool vo = false}) =>
        "serverEse: \"s\", portEse: \"80\", orariServer.push({ idEvento: 1, "
        "data: '2026-10-20', ora: '21.00', sala: \"A\", postiLiberi: $free, "
        "is3D: false, isVO: $vo, isAtmos: false, titolo: \"\" });";

    test('0 free seats is a real sold-out flag', () {
      expect(parseTwoTicketsCheckoutPage(push(0)).performances.single.isSoldOut,
          isTrue);
    });

    test('9999 means "not tracked" on 2Tickets, never sold out', () {
      expect(
        parseTwoTicketsCheckoutPage(push(9999)).performances.single.isSoldOut,
        isFalse,
      );
    });

    test('isVO is read', () {
      expect(
        parseTwoTicketsCheckoutPage(push(5, vo: true))
            .performances.single.isOriginalLanguage,
        isTrue,
      );
    });

    test('the page config bank fields are never part of the result', () {
      // Guard by construction: the result type has no field that could hold
      // them. This test documents the intent next to the parser.
      final p = parseTwoTicketsCheckoutPage(push(5));
      expect(p.serverEse, 's');
    });
  });

  group('2Tickets seat map', () {
    String fx(String name) =>
        File('test/fixtures/twotickets_$name').readAsStringSync();

    test('sectors: single numbered room', () {
      final s = parseTwoTicketsSectors(fx('settori_single.json')).single;
      expect(s.id, 3577);
      expect(s.name, 'Platea');
      expect(s.isNumbered, isTrue);
      expect(s.freeSeats, 70);
    });

    test('sectors: Orfeo Taranto has 7 numbered sectors', () {
      final sectors = parseTwoTicketsSectors(fx('settori_multi.json'));
      expect(sectors, hasLength(7));
      expect(sectors.every((s) => s.isNumbered), isTrue);
      expect(sectors.first.name, 'PLATEA');
    });

    test('sectors: Posto Unico is unnumbered', () {
      final s = parseTwoTicketsSectors(fx('settori_unnumbered.json')).single;
      expect(s.isNumbered, isFalse);
      expect(s.freeSeats, 60);
      expect(s.capacity, 60);
    });

    test('this is the actual feature: a real sold-out-ish room - 22 sold '
        'seats (stato 201, isVenduto) read as occupied, 516 free, gaps '
        'are aisles', () {
      const sector = TwoTicketsSector(
        id: 4467, name: 'PLATEA', hall: 'MAGNUM NUM',
        isNumbered: true, freeSeats: 516, capacity: 538,
      );
      final map = buildTwoTicketsSeatMap(TwoTicketsSeatMapPayload(
        sectors: [sector],
        seatsJsonBySectorId: {4467: fx('posti_sold.json')},
      ));
      expect(map.totalSeatCount, 538);
      expect(map.availableSeatCount, 516);
      expect(map.occupiedSeatCount, 22);
      expect(map.rows, hasLength(23));
      expect(map.totalColumns, 30);
      // Row 0 is nearest the screen; its two blocks are spelled AA/A.
      expect(map.rows.first.rowLabel, 'A');
      final gg3 = map.rows[7].seats.whereType<Seat>()
          .firstWhere((s) => s.name == 'GG3');
      expect(gg3.status, SeatStatus.occupied);
    });

    test('an empty room: every seat available', () {
      const sector = TwoTicketsSector(
        id: 3577, name: 'Platea', hall: 'NORBA 3',
        isNumbered: true, freeSeats: 70, capacity: 70,
      );
      final map = buildTwoTicketsSeatMap(TwoTicketsSeatMapPayload(
        sectors: [sector],
        seatsJsonBySectorId: {3577: fx('posti_empty.json')},
      ));
      expect(map.totalSeatCount, 70);
      expect(map.availableSeatCount, 70);
      expect(map.screenLabel, 'NORBA 3');
    });

    test('several numbered sectors stack, separated by one blank row, each '
        'its own legend category; an unnumbered sector alongside is kept', () {
      const a = TwoTicketsSector(
        id: 1, name: 'PLATEA', hall: 'S', isNumbered: true,
        freeSeats: 70, capacity: 773,
      );
      const b = TwoTicketsSector(
        id: 2, name: 'GALLERIA', hall: 'S', isNumbered: true,
        freeSeats: 70, capacity: 773,
      );
      const c = TwoTicketsSector(
        id: 3, name: 'LOGGIONE', hall: 'S', isNumbered: false,
        freeSeats: 30, capacity: 773,
      );
      final empty = fx('posti_empty.json');
      final map = buildTwoTicketsSeatMap(TwoTicketsSeatMapPayload(
        sectors: [a, b, c],
        seatsJsonBySectorId: {1: empty, 2: empty},
      ));
      expect(map.rows, hasLength(8 + 1 + 8));
      expect(map.rows[8].seats.whereType<Seat>(), isEmpty);
      expect(map.areaCategories.map((x) => x.name), ['PLATEA', 'GALLERIA']);
      // Review Focus 4: in a multi-sector room `capienza` is room-wide, so
      // the unnumbered sector's capacity is unknown, not 773.
      expect(map.unnumberedSectors.single.capacity, isNull);
      expect(map.unnumberedSectors.single.freeSeats, 30);
    });
  });
}
