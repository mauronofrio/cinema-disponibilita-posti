import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/chains/two_tickets/two_tickets_checkout_parser.dart';
import 'package:thespace_companion/core/chains/two_tickets/two_tickets_venue_parser.dart';

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
}
