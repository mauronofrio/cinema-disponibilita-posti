import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
