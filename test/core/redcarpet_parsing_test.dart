import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/chains/redcarpet/redcarpet_film_parser.dart';
import 'package:thespace_companion/core/chains/redcarpet/redcarpet_seat_map_parser.dart';
import 'package:thespace_companion/core/models/seat_map.dart';

void main() {
  group('parseRedCarpetFilmList', () {
    test(
      'reads title/id/poster out of each .movie--preview card, no duplicates',
      () {
        final html = File(
          'test/fixtures/redcarpet_homepage_sample.html',
        ).readAsStringSync();
        final films = parseRedCarpetFilmList(html);
        expect(films, isNotEmpty);
        final minions = films.firstWhere((f) => f.filmId == '104288');
        expect(minions.title, 'MINIONS & MONSTERS');
        expect(minions.posterUrl, isNotNull);
        // Each card's title link appears more than once (title + poster
        // anchor) - must still only produce one entry per film id.
        expect(films.where((f) => f.filmId == '104288'), hasLength(1));
      },
    );
  });

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

  group('parseRedCarpetFilmOccupations', () {
    late String html;

    setUpAll(() {
      html = File(
        'test/fixtures/redcarpet_occupations_sample.html',
      ).readAsStringSync();
    });

    test(
      'reads every showtime with its session/theater ids and start time',
      () {
        final sessions = parseRedCarpetFilmOccupations(html);
        expect(sessions, hasLength(6));
        // Confirmed against the real page: Sala 2, 17:00, on 2026-07-18.
        final first = sessions.firstWhere(
          (s) => s.sessionId == '62101f19-8432-4c57-b557-28ac546c0b32',
        );
        expect(first.theaterId, 'c54a8696-90b4-4621-a0df-0687b035a7e1');
        expect(first.theaterName, 'Sala 2');
        expect(first.startTime, DateTime(2026, 7, 18, 17, 0));
      },
    );

    test('sessionId is unique per showtime', () {
      final sessions = parseRedCarpetFilmOccupations(html);
      expect(
        sessions.map((s) => s.sessionId).toSet(),
        hasLength(sessions.length),
      );
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
