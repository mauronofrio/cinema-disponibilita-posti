import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/chains/eighteen_tickets/eighteen_tickets_film_parser.dart';
import 'package:thespace_companion/core/chains/eighteen_tickets/eighteen_tickets_seat_map_parser.dart';
import 'package:thespace_companion/core/models/seat_map.dart';

void main() {
  group('parseEighteenTicketsProgrammingDays', () {
    test('reads every day balloon, in order', () {
      final html = File(
        'test/fixtures/eighteen_tickets_homepage_sample.html',
      ).readAsStringSync();
      final days = parseEighteenTicketsProgrammingDays(html);
      expect(days, isNotEmpty);
      expect(days, orderedEquals(days.toList()..sort()));
      expect(
        days.every((d) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d)),
        isTrue,
      );
    });
  });

  group('parseEighteenTicketsFilmsForDay', () {
    late String html;

    setUpAll(() {
      html = File(
        'test/fixtures/eighteen_tickets_films_for_day_sample.html',
      ).readAsStringSync();
    });

    test('reads every film shown that day, no duplicates', () {
      final programming = parseEighteenTicketsFilmsForDay(
        html,
        DateTime(2026, 7, 8),
      );
      expect(programming.films, hasLength(11));
      final minions = programming.films.firstWhere((f) => f.filmId == '104288');
      expect(minions.title, 'MINIONS & MONSTERS');
      expect(minions.posterUrl, isNotNull);
      // "MINIONS & MONSTERS - 3D" is a distinct film id (104783), not a
      // duplicate of the 2D version - both should show up separately.
      expect(programming.films.any((f) => f.filmId == '104783'), isTrue);
    });

    test('reads every showtime for every film, with its own room and time', () {
      final programming = parseEighteenTicketsFilmsForDay(
        html,
        DateTime(2026, 7, 8),
      );
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
      final programming = parseEighteenTicketsFilmsForDay(
        html,
        DateTime(2026, 7, 8),
      );
      expect(
        programming.sessions.map((s) => s.sessionId).toSet(),
        hasLength(programming.sessions.length),
      );
    });
  });

  group('parseEighteenTicketsTheaterIdForSession', () {
    test(
      'finds the room for the matching session id, not just the first one on the page',
      () {
        final html = File(
          'test/fixtures/eighteen_tickets_film_session_page_sample.html',
        ).readAsStringSync();
        final theaterId = parseEighteenTicketsTheaterIdForSession(
          html,
          'a25a4245-7ea1-471d-a162-48cb62340956',
        );
        expect(theaterId, 'a6d7bb70-9793-4c32-bf5b-bedc866d30c9');
      },
    );

    test('returns null for a session id not present on the page', () {
      final html = File(
        'test/fixtures/eighteen_tickets_film_session_page_sample.html',
      ).readAsStringSync();
      expect(
        parseEighteenTicketsTheaterIdForSession(html, 'not-a-real-id'),
        isNull,
      );
    });
  });

  group('parseEighteenTicketsSeatMap', () {
    late String svg;
    late String emptyOccupancy;

    setUpAll(() {
      svg = File(
        'test/fixtures/eighteen_tickets_theater_sample.svg',
      ).readAsStringSync();
      emptyOccupancy = File(
        'test/fixtures/eighteen_tickets_seats_sample.json',
      ).readAsStringSync();
    });

    test(
      'every non-accessibility seat is available when the occupancy response lists nothing busy',
      () {
        final seatMap = parseEighteenTicketsSeatMap(
          EighteenTicketsSeatMapPayload(
            theaterSvg: svg,
            occupancyJson: emptyOccupancy,
          ),
        );
        final seats = seatMap.rows
            .expand((r) => r.seats)
            .whereType<Seat>()
            .toList();
        expect(seats, isNotEmpty);
        expect(
          seats
              .where((s) => !s.isAccessibility)
              .every((s) => s.status == SeatStatus.available),
          isTrue,
        );
      },
    );

    test(
      'accessibility seats (class "special userhide") are flagged and given their own status when free',
      () {
        final seatMap = parseEighteenTicketsSeatMap(
          EighteenTicketsSeatMapPayload(
            theaterSvg: svg,
            occupancyJson: emptyOccupancy,
          ),
        );
        final seats = seatMap.rows.expand((r) => r.seats).whereType<Seat>();
        final accessibilitySeats = seats
            .where((s) => s.isAccessibility)
            .toList();
        expect(accessibilitySeats, isNotEmpty);
        expect(
          accessibilitySeats.every((s) => s.status == SeatStatus.accessibility),
          isTrue,
        );
      },
    );

    test('rows are ordered by label, descending, screen-side first', () {
      final seatMap = parseEighteenTicketsSeatMap(
        EighteenTicketsSeatMapPayload(
          theaterSvg: svg,
          occupancyJson: emptyOccupancy,
        ),
      );
      // Row "A" is always the back row on this platform - it must render
      // last, not first, in the returned row list.
      expect(seatMap.rows.first.rowLabel, isNot('A'));
      expect(seatMap.rows.last.rowLabel, 'A');
    });

    test(
      'seat labels combine row letter and seat number, not the raw grid id',
      () {
        final seatMap = parseEighteenTicketsSeatMap(
          EighteenTicketsSeatMapPayload(
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
        final seatMap = parseEighteenTicketsSeatMap(
          EighteenTicketsSeatMapPayload(
            theaterSvg: svg,
            occupancyJson: occupancy,
          ),
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
        final seatMap = parseEighteenTicketsSeatMap(
          EighteenTicketsSeatMapPayload(
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

    test(
      'row order follows the label, descending, even in a room whose real y runs the opposite way for every row',
      () {
        // A real Multicinema Galleria room (a Backrooms screening) where
        // *every* row's real y runs the opposite direction from every other
        // room checked (row "A" lowest/closest, each later letter higher) -
        // not just row "A" out of place. Real y can't be trusted
        // platform-wide, so row order always follows the label itself
        // (descending) regardless of what the SVG's own geometry says.
        final reversedSvg = File(
          'test/fixtures/eighteen_tickets_theater_reversed_row_a_sample.svg',
        ).readAsStringSync();
        final seatMap = parseEighteenTicketsSeatMap(
          EighteenTicketsSeatMapPayload(
            theaterSvg: reversedSvg,
            occupancyJson: emptyOccupancy,
          ),
        );
        expect(seatMap.rows.map((r) => r.rowLabel).toList(), [
          'H',
          'G',
          'F',
          'E',
          'D',
          'C',
          'B',
          'A',
        ]);
      },
    );

    test(
      'a "DD" row label is merged into "A" instead of rendered as its own row',
      () {
        // A real room where a lone companion/accessible seat is labelled
        // "DD" in the raw SVG despite sitting on the exact same physical
        // line as row A - not a real row of its own.
        final ddSvg = File(
          'test/fixtures/eighteen_tickets_theater_dd_row_sample.svg',
        ).readAsStringSync();
        final seatMap = parseEighteenTicketsSeatMap(
          EighteenTicketsSeatMapPayload(
            theaterSvg: ddSvg,
            occupancyJson: emptyOccupancy,
          ),
        );
        expect(seatMap.rows.any((r) => r.rowLabel == 'DD'), isFalse);
        final rowA = seatMap.rows.firstWhere((r) => r.rowLabel == 'A');
        final seats = rowA.seats.whereType<Seat>().toList();
        // The merged-in seat always carries the raw number "1", which
        // collides with the row's own real seat "1" - every seat in the row
        // must still get a unique name once merged.
        expect(seats.map((s) => s.name).toSet(), hasLength(seats.length));
      },
    );

    test(
      'a busy-array entry shaped as {"sid", "x", "y"} matches the seat whose SVG rect id is "y_x"',
      () {
        // Confirmed live on Multicinema Galleria: unlike RedCarpet's plain
        // seat-id strings (e.g. "11_7"), this room's occupancy response
        // lists reserved seats as objects - {"x": 6, "y": 10} here matches
        // real rect id "10_6" (row A, third seat), the same seat the user
        // reported as reserved.
        const occupancy =
            '{"bought":[],"locked":[],"reserved":[{"sid":31706,"x":6,"y":10}],"quarantined":[],"reselling":[],"mine":[],"preemption":[]}';
        final ddSvg = File(
          'test/fixtures/eighteen_tickets_theater_dd_row_sample.svg',
        ).readAsStringSync();
        final seatMap = parseEighteenTicketsSeatMap(
          EighteenTicketsSeatMapPayload(
            theaterSvg: ddSvg,
            occupancyJson: occupancy,
          ),
        );
        final busySeats = seatMap.rows
            .expand((r) => r.seats)
            .whereType<Seat>()
            .where((s) => s.status == SeatStatus.reserved)
            .toList();
        expect(busySeats, hasLength(1));
      },
    );
  });
}
