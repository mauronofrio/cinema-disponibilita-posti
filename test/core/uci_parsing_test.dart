import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/chains/uci/uci_film_parser.dart';
import 'package:thespace_companion/core/chains/uci/uci_seat_map_parser.dart';
import 'package:thespace_companion/core/models/film.dart';
import 'package:thespace_companion/core/models/seat_map.dart';

void main() {
  group('parseUciProgrammingDay', () {
    late List<dynamic> filmsJson;

    setUpAll(() {
      final raw = File(
        'test/fixtures/uci_programming_sample.json',
      ).readAsStringSync();
      filmsJson =
          (json.decode(raw) as Map<String, dynamic>)['data'] as List<dynamic>;
    });

    test(
      'flattens every format/variant performance into one session list per film',
      () {
        final date = DateTime(2026, 7, 7);
        final days = parseUciProgrammingDay(filmsJson, date);
        final minions = days.firstWhere((d) => d.title == 'Minions & Monsters');
        // The real cinema this fixture came from shows it 8 times that day
        // across 3 rooms (Sala 7/5/1) - see PROJECT_NOTES.md.
        expect(minions.sessions, hasLength(8));
        expect(minions.sessions.map((s) => s.sessionId), contains('83114'));
      },
    );

    test(
      'carries room_id through as webticScreenId, matching a known real session',
      () {
        final date = DateTime(2026, 7, 7);
        final days = parseUciProgrammingDay(filmsJson, date);
        final minions = days.firstWhere((d) => d.title == 'Minions & Monsters');
        // Confirmed against a real booking: session 83114 is Sala 5, room_id 104.
        final session = minions.sessions.firstWhere(
          (s) => s.sessionId == '83114',
        );
        expect(session.webticScreenId, 104);
        expect(session.screenName, 'SALA 5');
      },
    );

    test('sessions within a film are sorted by start time', () {
      final date = DateTime(2026, 7, 7);
      final days = parseUciProgrammingDay(filmsJson, date);
      final minions = days.firstWhere((d) => d.title == 'Minions & Monsters');
      for (var i = 1; i < minions.sessions.length; i++) {
        expect(
          minions.sessions[i].startTime.isAfter(
            minions.sessions[i - 1].startTime,
          ),
          isTrue,
        );
      }
    });

    test(
      'every session carries a Language attribute, matching The Space\'s own '
      'convention - the real fixture is ITA-only, confirmed live at UCI '
      'Bicocca Milano for its "Oceania" showings',
      () {
        final date = DateTime(2026, 7, 7);
        final days = parseUciProgrammingDay(filmsJson, date);
        final minions = days.firstWhere((d) => d.title == 'Minions & Monsters');
        for (final session in minions.sessions) {
          final language = session.attributes.where(
            (a) => a.attributeType == 'Language',
          );
          expect(language, hasLength(1));
          expect(language.first.name, 'ITA');
        }
      },
    );

    test(
      'this is the actual feature: ITA and original-language (name "ENG") '
      'performances of the same film both get tagged, so they can be split '
      'into groups the same way The Space\'s ITALIANO/LINGUA ORIGINALE are',
      () {
        final mixedLanguageJson = jsonDecode('''
        {"data": [{
          "id": 1, "title": "Oceania", "slug": "oceania",
          "screens": [{"2D": [
            {
              "language": {"name": "ITA", "slug": "ITA"},
              "duration": "01:40",
              "performances": [
                {"external_id": 1, "starts_at": "2026-08-24 18:00:00", "ends_at": "2026-08-24 19:40:00", "room": "SALA 1"}
              ]
            },
            {
              "language": {"name": "ENG", "slug": "EN"},
              "duration": "01:40",
              "performances": [
                {"external_id": 2, "starts_at": "2026-08-24 14:00:00", "ends_at": "2026-08-24 15:40:00", "room": "SALA 6"}
              ]
            }
          ]}]
        }]}
        ''') as Map<String, dynamic>;
        final days = parseUciProgrammingDay(
          mixedLanguageJson['data'] as List<dynamic>,
          DateTime(2026, 8, 24),
        );
        final oceania = days.first;
        final groups = groupSessionsByLanguage(oceania.sessions);
        expect(groups.keys, containsAll(['ITA', 'ENG']));
        expect(groups['ITA'], hasLength(1));
        expect(groups['ENG'], hasLength(1));
      },
    );

    test('films with no performances that day are skipped entirely', () {
      final date = DateTime(2026, 7, 7);
      final days = parseUciProgrammingDay(filmsJson, date);
      // Every entry returned must actually have at least one session -
      // "not_today"/no-screens films shouldn't produce an empty ParsedUciDay.
      expect(days.every((d) => d.sessions.isNotEmpty), isTrue);
    });
  });

  group('parseUciSeatMap', () {
    late UciSeatMapPayload payload;

    setUpAll(() {
      payload = UciSeatMapPayload(
        screenResponseBody: File(
          'test/fixtures/uci_screen_sample.json',
        ).readAsStringSync(),
        occupancyResponseBody: File(
          'test/fixtures/uci_occupancy_sample.json',
        ).readAsStringSync(),
      );
    });

    test(
      'builds a row per distinct Row value, sized to the widest column seen',
      () {
        final seatMap = parseUciSeatMap(payload);
        // Seats A/1..A/20 sit at columns 2..21 in the fixture, nothing at
        // column 1, so the grid is 21 wide with an always-empty first slot.
        expect(seatMap.totalColumns, 21);
        expect(seatMap.rows, isNotEmpty);
      },
    );

    test(
      'a seat listed in Occupancy is occupied, matching the captured example',
      () {
        final seatMap = parseUciSeatMap(payload);
        final seat = seatMap.rows
            .expand((r) => r.seats)
            .whereType<Seat>()
            .firstWhere((s) => s.name == 'H/11');
        expect(seat.status, SeatStatus.occupied);
      },
    );

    test('a seat absent from Occupancy is available, not just "unknown"', () {
      final seatMap = parseUciSeatMap(payload);
      // C/1 never appears in the occupancy fixture and isn't a special
      // SeatType either, so it must read as a normal free seat.
      final seat = seatMap.rows
          .expand((r) => r.seats)
          .whereType<Seat>()
          .firstWhere((s) => s.name == 'C/1');
      expect(seat.status, SeatStatus.available);
    });

    test('DISABILE seats read as accessibility when not occupied', () {
      final seatMap = parseUciSeatMap(payload);
      final seat = seatMap.rows
          .expand((r) => r.seats)
          .whereType<Seat>()
          .firstWhere((s) => s.name == 'P.D.');
      expect(seat.status, SeatStatus.accessibility);
    });

    test('area categories come from Sectors, keyed by SectorId', () {
      final seatMap = parseUciSeatMap(payload);
      expect(seatMap.categoryFor('PT'), isNotNull);
      expect(seatMap.categoryFor('PT')!.color, '42A5F5');
    });

    test(
      'accessibility seats (SeatType DISABILE) are flagged and excluded from occupancy counts',
      () {
        final seatMap = parseUciSeatMap(payload);
        final allSeats = seatMap.rows
            .expand((r) => r.seats)
            .whereType<Seat>()
            .toList();
        final accessibilitySeats = allSeats
            .where((s) => s.isAccessibility)
            .toList();
        // The fixture's HX row (P.D. x2) are the only DISABILE seats.
        expect(accessibilitySeats, hasLength(2));
        expect(seatMap.totalSeatCount, allSeats.length - 2);
      },
    );
  });
}
