import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/chains/redcarpet/redcarpet_film_parser.dart';
import 'package:thespace_companion/core/chains/redcarpet/redcarpet_seat_map_parser.dart';
import 'package:thespace_companion/core/models/seat_map.dart';

void main() {
  group('parseRedCarpetProgrammingDays', () {
    test('reads every day balloon, in order', () {
      final html = File(
        'test/fixtures/redcarpet_homepage_sample.html',
      ).readAsStringSync();
      final days = parseRedCarpetProgrammingDays(html);
      expect(days, isNotEmpty);
      expect(days, orderedEquals(days.toList()..sort()));
      expect(
        days.every((d) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d)),
        isTrue,
      );
    });
  });

  group('parseRedCarpetFilmsForDay', () {
    late String html;

    setUpAll(() {
      html = File(
        'test/fixtures/redcarpet_films_for_day_sample.html',
      ).readAsStringSync();
    });

    test('reads every film shown that day, no duplicates', () {
      final programming = parseRedCarpetFilmsForDay(html, DateTime(2026, 7, 8));
      expect(programming.films, hasLength(11));
      final minions = programming.films.firstWhere((f) => f.filmId == '104288');
      expect(minions.title, 'MINIONS & MONSTERS');
      expect(minions.posterUrl, isNotNull);
      // "MINIONS & MONSTERS - 3D" is a distinct film id (104783), not a
      // duplicate of the 2D version - both should show up separately.
      expect(programming.films.any((f) => f.filmId == '104783'), isTrue);
    });

    test('reads every showtime for every film, with its own room and time', () {
      final programming = parseRedCarpetFilmsForDay(html, DateTime(2026, 7, 8));
      // MINIONS & MONSTERS has 5 showtimes that day, across rooms 7/1/7/7/1.
      final minionsSessions = programming.sessions
          .where((s) => s.filmId == '104288')
          .toList();
      expect(minionsSessions, hasLength(5));
      final first = minionsSessions.firstWhere(
        (s) => s.sessionId == 'c5257510-9f6e-4a1b-a5eb-3386ce1114c1',
      );
      expect(first.theaterName, 'Sala 7');
      expect(first.startTime, DateTime(2026, 7, 8, 17, 0));
    });

    test('sessionId is unique across every film/showtime that day', () {
      final programming = parseRedCarpetFilmsForDay(html, DateTime(2026, 7, 8));
      expect(
        programming.sessions.map((s) => s.sessionId).toSet(),
        hasLength(programming.sessions.length),
      );
    });
  });

  group('parseRedCarpetTheaterIdForSession', () {
    test(
      'finds the room for the matching session id, not just the first one on the page',
      () {
        final html = File(
          'test/fixtures/redcarpet_film_session_page_sample.html',
        ).readAsStringSync();
        final theaterId = parseRedCarpetTheaterIdForSession(
          html,
          'a25a4245-7ea1-471d-a162-48cb62340956',
        );
        expect(theaterId, 'a6d7bb70-9793-4c32-bf5b-bedc866d30c9');
      },
    );

    test('returns null for a session id not present on the page', () {
      final html = File(
        'test/fixtures/redcarpet_film_session_page_sample.html',
      ).readAsStringSync();
      expect(parseRedCarpetTheaterIdForSession(html, 'not-a-real-id'), isNull);
    });
  });

  group('parseRedCarpetSeatMap', () {
    late String svg;
    late String emptyOccupancy;

    setUpAll(() {
      svg = File(
        'test/fixtures/redcarpet_theater_sample.svg',
      ).readAsStringSync();
      emptyOccupancy = File(
        'test/fixtures/redcarpet_seats_sample.json',
      ).readAsStringSync();
    });

    test(
      'every seat is available when the occupancy response lists nothing busy',
      () {
        final seatMap = parseRedCarpetSeatMap(
          RedCarpetSeatMapPayload(
            theaterSvg: svg,
            occupancyJson: emptyOccupancy,
          ),
        );
        final seats = seatMap.rows
            .expand((r) => r.seats)
            .whereType<Seat>()
            .toList();
        expect(seats, isNotEmpty);
        expect(seats.every((s) => s.status == SeatStatus.available), isTrue);
      },
    );

    test(
      'seat labels combine row letter and seat number, not the raw grid id',
      () {
        final seatMap = parseRedCarpetSeatMap(
          RedCarpetSeatMapPayload(
            theaterSvg: svg,
            occupancyJson: emptyOccupancy,
          ),
        );
        final seats = seatMap.rows.expand((r) => r.seats).whereType<Seat>();
        expect(seats.any((s) => s.name == 'A15'), isTrue);
      },
    );

    test(
      'a seat id present in "bought" reads as occupied, "reserved" as reserved',
      () {
        // A15's grid id is "11_7" per the real SVG sample - synthesize an
        // occupancy response marking it bought, and a second seat reserved,
        // to exercise the merge logic (the live example had nothing busy).
        const occupancy =
            '{"bought":["11_7"],"locked":[],"reserved":["11_8"],"quarantined":[],"reselling":[],"mine":[],"preemption":[]}';
        final seatMap = parseRedCarpetSeatMap(
          RedCarpetSeatMapPayload(theaterSvg: svg, occupancyJson: occupancy),
        );
        final seats = seatMap.rows
            .expand((r) => r.seats)
            .whereType<Seat>()
            .toList();
        expect(
          seats.firstWhere((s) => s.name == 'A15').status,
          SeatStatus.occupied,
        );
        expect(
          seats.firstWhere((s) => s.name == 'A14').status,
          SeatStatus.reserved,
        );
      },
    );

    test(
      'column order follows real x position, not the (unreliable) data-seat number',
      () {
        final seatMap = parseRedCarpetSeatMap(
          RedCarpetSeatMapPayload(
            theaterSvg: svg,
            occupancyJson: emptyOccupancy,
          ),
        );
        final rowA = seatMap.rows.firstWhere((r) => r.rowLabel == 'A');
        // A15 sits left of A14 in the real SVG (x=162.5 vs x=187.5) - seat
        // *numbers* decrease left-to-right in this room, so trusting them for
        // order would reverse the row.
        final indexOfA15 = rowA.seats.indexWhere((s) => s?.name == 'A15');
        final indexOfA14 = rowA.seats.indexWhere((s) => s?.name == 'A14');
        expect(indexOfA15, lessThan(indexOfA14));
      },
    );
  });
}
