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

    test(
      'a showtime with no room name after the time (Circuito Cinema / '
      'Multisala Impero template) still counts as a session, with an '
      'empty theaterName rather than being dropped',
      () {
        final noRoomHtml = File(
          'test/fixtures/eighteen_tickets_films_for_day_no_room_sample.html',
        ).readAsStringSync();
        final programming = parseEighteenTicketsFilmsForDay(
          noRoomHtml,
          DateTime(2026, 7, 8),
        );
        expect(programming.films, isNotEmpty);
        expect(programming.sessions, isNotEmpty);
        expect(programming.sessions.every((s) => s.theaterName == ''), isTrue);
      },
    );

    test(
      'this is the actual feature: two distinct films that collide on the '
      'exact same title (RedCarpet Monopoli lists a regular and a '
      'sing-along "OCEANIA (MOANA)" as separate catalog entries with no '
      'other visible difference) get the labeled one\'s badge appended, so '
      'they read as two different cards instead of duplicates',
      () {
        final dupHtml = File(
          'test/fixtures/eighteen_tickets_duplicate_title_sample.html',
        ).readAsStringSync();
        final programming = parseEighteenTicketsFilmsForDay(
          dupHtml,
          DateTime(2026, 8, 24),
        );
        expect(programming.films, hasLength(2));
        final regular = programming.films.firstWhere(
          (f) => f.filmId == '113627',
        );
        final singAlong = programming.films.firstWhere(
          (f) => f.filmId == '114287',
        );
        expect(regular.title, 'OCEANIA (MOANA)');
        expect(singAlong.title, 'OCEANIA (MOANA) · 🎤 Sing-Along');
      },
    );

    test(
      'a lone film keeps its plain title even if it happens to carry a '
      'label - only an actual title collision triggers disambiguation',
      () {
        final soloHtml = File(
          'test/fixtures/eighteen_tickets_lone_labeled_film_sample.html',
        ).readAsStringSync();
        final programming = parseEighteenTicketsFilmsForDay(
          soloHtml,
          DateTime(2026, 8, 24),
        );
        expect(programming.films, hasLength(1));
        expect(programming.films.single.title, 'OCEANIA (MOANA)');
      },
    );

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

  group('parseEighteenTicketsAllSessionsForFilm', () {
    test(
      'reads every real showtime off a film\'s fetch_film_occupations response, with its real date/time',
      () {
        // Multisala Massimo - Lecce, confirmed live: TOY STORY 5's
        // fetch_film_occupations response lists both of its real showtimes
        // for Wednesday 08/07/2026, even though this cinema's `fetch_films`
        // response for that same day renders zero showtime markup at all.
        final html = File(
          'test/fixtures/eighteen_tickets_film_occupations_sample.html',
        ).readAsStringSync();
        final sessions = parseEighteenTicketsAllSessionsForFilm(
          html,
          '105201',
        );
        expect(sessions, hasLength(2));
        expect(sessions.every((s) => s.filmId == '105201'), isTrue);
        final first = sessions.firstWhere(
          (s) => s.sessionId == '981b4316-1664-4563-939e-c76d673881ce',
        );
        expect(first.startTime, DateTime(2026, 7, 8, 18, 45));
        final second = sessions.firstWhere(
          (s) => s.sessionId == '82a1dadd-dd73-4d0d-a0fb-041faf6eadb8',
        );
        expect(second.startTime, DateTime(2026, 7, 8, 20, 45));
      },
    );
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

    test('rows are ordered by real distance from the screen, closest first', () {
      final seatMap = parseEighteenTicketsSeatMap(
        EighteenTicketsSeatMapPayload(
          theaterSvg: svg,
          occupancyJson: emptyOccupancy,
        ),
      );
      // In this room's SVG, row "A" sits at the highest y - farthest from
      // the screen (drawn at y=10) - so it must render last.
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
      'row order still follows real distance from the screen in a room built the opposite way round',
      () {
        // A real Multicinema Galleria room (a Backrooms screening) whose SVG
        // geometry runs the opposite direction from every other room checked
        // (row "A" nearest the screen, each later letter farther) - confirmed
        // live against the actual booking page to be a real, intentional
        // layout, not a data quirk. Distance-from-screen still gets this
        // right without any special-casing, because it reads whatever this
        // room's own screen element and rows actually say, room by room.
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
          'A',
          'B',
          'C',
          'D',
          'E',
          'F',
          'G',
          'H',
        ]);
      },
    );

    test(
      'a room whose screen sits at the bottom of its own SVG puts row "A" first, not last',
      () {
        // Multisala Massimo - Lecce, confirmed live against the real booking
        // page: the screen is drawn at y=280 (below every row), and row "A"
        // is the closest row to it (y=222.5) - the platform-wide "A is
        // always the back row" assumption doesn't hold here.
        final screenAtBottomSvg = File(
          'test/fixtures/eighteen_tickets_theater_screen_at_bottom_sample.svg',
        ).readAsStringSync();
        final seatMap = parseEighteenTicketsSeatMap(
          EighteenTicketsSeatMapPayload(
            theaterSvg: screenAtBottomSvg,
            occupancyJson: emptyOccupancy,
          ),
        );
        expect(seatMap.rows.first.rowLabel, 'A');
        expect(seatMap.rows.last.rowLabel, isNot('A'));
      },
    );

    test(
      'a "special userhide" seat with a non-empty data-note is left out of the room entirely, not shown as accessibility',
      () {
        // Multisala Massimo - Lecce's largest room, confirmed live: roughly
        // a third of its ~700 seats carry the exact same "special userhide"
        // class real accessibility seats use elsewhere on this platform,
        // but tagged `data-note='Galleria'` - reusing the class for a whole
        // upper section, not individual companion seats, and never really
        // bookable - so they're gaps in the grid, not accessibility seats
        // and not a "special" placeholder either.
        final gallerySvg = File(
          'test/fixtures/eighteen_tickets_theater_reused_class_gallery_sample.svg',
        ).readAsStringSync();
        final seatMap = parseEighteenTicketsSeatMap(
          EighteenTicketsSeatMapPayload(
            theaterSvg: gallerySvg,
            occupancyJson: emptyOccupancy,
          ),
        );
        final seats = seatMap.rows.expand((r) => r.seats).whereType<Seat>();
        expect(seats.where((s) => s.isAccessibility), isEmpty);
        expect(seats.where((s) => s.status == SeatStatus.special), isEmpty);
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
      'row order is computed after dropping not-for-sale seats, so a '
      'gallery that reuses the stalls\' row letters (Multisala Massimo - '
      'Lecce) does not scramble the front-to-back order',
      () {
        // Real fixture, confirmed live: grouping by row label before
        // filtering isNotForSale produced
        // "A, B, O, P, Q, M, R, N, C, S, D, T, F, G, L, H, E, I, U" because
        // 15 of 19 row letters are shared between the stalls and the
        // gallery above them, dragging each shared letter's average y
        // toward the gallery. Filtering first restores plain A...U.
        final gallerySvg = File(
          'test/fixtures/eighteen_tickets_theater_reused_class_gallery_sample.svg',
        ).readAsStringSync();
        final seatMap = parseEighteenTicketsSeatMap(
          EighteenTicketsSeatMapPayload(
            theaterSvg: gallerySvg,
            occupancyJson: emptyOccupancy,
          ),
        );
        expect(seatMap.rows.map((r) => r.rowLabel).toList(), [
          'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'L',
          'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U',
        ]);
      },
    );

    test(
      'a row label that only exists in the not-for-sale gallery section is '
      'dropped entirely, not rendered as a fully blank row',
      () {
        // Synthetic minimal SVG: row "A" has two real, bookable seats; row
        // "Z" only ever appears tagged "special userhide" with a non-empty
        // data-note (the gallery marker) - it should never surface as a row
        // at all once isNotForSale seats are filtered out before grouping.
        const svg = '''
<svg>
<rect class='m18-th-screen' x='0' y='10' width='100' height='5'></rect>
<g class='posto' data-area='PT' data-row='A' data-seat='1'>
<rect id='1_1' x='10' y='100'></rect>
</g>
<g class='posto' data-area='PT' data-row='A' data-seat='2'>
<rect id='1_2' x='30' y='100'></rect>
</g>
<g class='posto special userhide' data-area='PT' data-row='Z' data-seat='1' data-note='Galleria'>
<rect id='2_1' x='10' y='200'></rect>
</g>
</svg>
''';
        final seatMap = parseEighteenTicketsSeatMap(
          EighteenTicketsSeatMapPayload(
            theaterSvg: svg,
            occupancyJson: emptyOccupancy,
          ),
        );
        expect(seatMap.rows.map((r) => r.rowLabel).toList(), ['A']);
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
