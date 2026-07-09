import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/chains/webtic/webtic_film_parser.dart';
import 'package:thespace_companion/core/chains/webtic/webtic_film_schedule_page_parser.dart';
import 'package:thespace_companion/core/chains/webtic/webtic_programming_page_parser.dart';
import 'package:thespace_companion/core/chains/webtic/webtic_seat_map_parser.dart';
import 'package:thespace_companion/core/models/seat_map.dart';

void main() {
  group('parseWebticFullSchedule', () {
    late String raw;

    setUpAll(() {
      raw = File(
        'test/fixtures/webtic_full_schedule_sample.json',
      ).readAsStringSync();
    });

    test('parses every film in the catalog, real Notorious Cagliari sample', () {
      final films = parseWebticFullSchedule(raw);
      expect(films, hasLength(16));
    });

    test(
      'groups multiple same-day performances under the one calendar day, real sessions',
      () {
        final films = parseWebticFullSchedule(raw);
        final odissea = films.firstWhere((f) => f.eventId == '1464');
        expect(odissea.title, '(O.V.) Odissea');
        final day = DateTime(2026, 7, 16);
        final sessions = odissea.sessionsByDay[day]!;
        expect(sessions, hasLength(2));
        expect(sessions.map((s) => s.performanceId), containsAll(['45019', '45026']));
        expect(sessions.every((s) => s.screenName == 'SALA 3'), isTrue);
        expect(sessions.every((s) => s.screenId == 235), isTrue);
      },
    );

    test('"HH:MM" Duration is converted to total minutes', () {
      final films = parseWebticFullSchedule(raw);
      final odissea = films.firstWhere((f) => f.eventId == '1464');
      // "02:52" in the raw fixture.
      expect(odissea.runningTimeMinutes, 172);
    });

    test('poster path is kept raw, unprefixed (chain_api adds the base URL)', () {
      final films = parseWebticFullSchedule(raw);
      final odissea = films.firstWhere((f) => f.eventId == '1464');
      expect(
        odissea.posterPath,
        'HandlerLocandinaEx.ashx?idcinema=5631&idevento=1464&i=jpg-m&t=150620261625',
      );
    });
  });

  group(
    'parseWebticFullSchedule (fullSchedulePortal - restapi.webtic.it wrapper, real Nuovo Eden sample)',
    () {
      late String raw;

      setUpAll(() {
        raw = File(
          'test/fixtures/webtic_nuovoeden_fullschedule_portal_sample.json',
        ).readAsStringSync();
      });

      test(
        'same DS.Scheduling.Events shape as the classic front-end, no new parser needed',
        () {
          final films = parseWebticFullSchedule(raw);
          expect(films, hasLength(2));
          final film = films.firstWhere((f) => f.eventId == '6446');
          expect(film.title, 'Amarga Navidad');
          expect(film.runningTimeMinutes, 111);
          final day = DateTime(2026, 7, 10);
          final sessions = film.sessionsByDay[day]!;
          expect(sessions.single.performanceId, '35974');
          expect(sessions.single.screenName, 'NUOVO EDEN');
          expect(sessions.single.screenId, 73);
        },
      );
    },
  );

  group('parseWebticShowingDays', () {
    test('every distinct day across every film, sorted with no duplicates', () {
      final raw = File(
        'test/fixtures/webtic_full_schedule_sample.json',
      ).readAsStringSync();
      final days = parseWebticShowingDays(raw);
      expect(days, isNotEmpty);
      expect(days.first, DateTime(2026, 7, 9));
      for (var i = 1; i < days.length; i++) {
        expect(days[i].isAfter(days[i - 1]), isTrue);
      }
    });
  });

  group('parseWebticSeatMap', () {
    late WebticSeatMapPayload payload;

    setUpAll(() {
      payload = WebticSeatMapPayload(
        mapSeatsResponseBody: File(
          'test/fixtures/webtic_map_seats_sample.json',
        ).readAsStringSync(),
        occupancyResponseBody: File(
          'test/fixtures/webtic_occupancy_sample.json',
        ).readAsStringSync(),
      );
    });

    test('builds a row per distinct fila, sized to the widest colonna seen', () {
      final seatMap = parseWebticSeatMap(payload);
      // Real Notorious Cagliari room (idsala 237): filas 2..6, max colonna 17.
      expect(seatMap.rows, hasLength(5));
      expect(seatMap.totalColumns, 17);
    });

    test('a seat listed in Occupancy is occupied even if tipologia is RISERVATO', () {
      final seatMap = parseWebticSeatMap(payload);
      final seat = seatMap.rows
          .expand((r) => r.seats)
          .whereType<Seat>()
          .firstWhere((s) => s.name == 'A/9');
      expect(seat.status, SeatStatus.occupied);
    });

    test('a STANDARD seat absent from Occupancy is available', () {
      final seatMap = parseWebticSeatMap(payload);
      final seat = seatMap.rows
          .expand((r) => r.seats)
          .whereType<Seat>()
          .firstWhere((s) => s.name == 'A/8');
      expect(seat.status, SeatStatus.available);
    });

    test('area categories come from distinct settore codes', () {
      final seatMap = parseWebticSeatMap(payload);
      expect(seatMap.categoryFor('PT'), isNotNull);
    });

    test(
      'a free RISERVATO seat (not in Occupancy) reads as reserved, not available',
      () {
        // No such example exists in the live-captured fixture (every
        // RISERVATO seat in it happens to also be occupied) - a small
        // hand-built payload covers the branch directly instead.
        const mapSeatsJson = '''
        {"DS":{"MapSeats":{"posti":[
          {"idposto":"A/1","fila":1,"colonna":1,"alias":"A/1","settore":"PT","tipologia":"RISERVATO"}
        ]}}}
        ''';
        const occupancyJson = '{"DS":{"Occupancy":{"posti":[]}}}';
        final seatMap = parseWebticSeatMap(
          WebticSeatMapPayload(
            mapSeatsResponseBody: mapSeatsJson,
            occupancyResponseBody: occupancyJson,
          ),
        );
        final seat = seatMap.rows.expand((r) => r.seats).whereType<Seat>().first;
        expect(seat.status, SeatStatus.reserved);
      },
    );

    test('a DISABILE seat is flagged as accessibility', () {
      const mapSeatsJson = '''
      {"DS":{"MapSeats":{"posti":[
        {"idposto":"P.D.","fila":1,"colonna":1,"alias":"P.D.","settore":"PT","tipologia":"DISABILE"}
      ]}}}
      ''';
      const occupancyJson = '{"DS":{"Occupancy":{"posti":[]}}}';
      final seatMap = parseWebticSeatMap(
        WebticSeatMapPayload(
          mapSeatsResponseBody: mapSeatsJson,
          occupancyResponseBody: occupancyJson,
        ),
      );
      final seat = seatMap.rows.expand((r) => r.seats).whereType<Seat>().first;
      expect(seat.isAccessibility, isTrue);
    });
  });

  group('parseWebticSeatMap (Giometti Cinema - ACCOMPAGNATORE seats)', () {
    late WebticSeatMapPayload payload;

    setUpAll(() {
      payload = WebticSeatMapPayload(
        mapSeatsResponseBody: File(
          'test/fixtures/webtic_giometti_map_seats_sample.json',
        ).readAsStringSync(),
        occupancyResponseBody: File(
          'test/fixtures/webtic_giometti_occupancy_sample.json',
        ).readAsStringSync(),
      );
    });

    test(
      'an ACCOMPAGNATORE seat (companion seat next to a wheelchair spot) reads as accessibility',
      () {
        // Real Multiplex Giometti Pesaro room (idsala 74): A/12 and A/8
        // are ACCOMPAGNATORE, confirmed live by the user in the physical
        // room - flanking a genuine 3-column gap (the wheelchair spot
        // itself, never listed in `posti` at all).
        final seatMap = parseWebticSeatMap(payload);
        final seat = seatMap.rows
            .expand((r) => r.seats)
            .whereType<Seat>()
            .firstWhere((s) => s.name == 'A/12');
        expect(seat.isAccessibility, isTrue);
      },
    );

    test(
      'the wheelchair spot itself is a real gap, not a rendered seat',
      () {
        final seatMap = parseWebticSeatMap(payload);
        final rowA = seatMap.rows.firstWhere((r) => r.rowLabel == 'A');
        // A/8 sits at colonna 12 and A/12 at colonna 8 (aliases run right
        // to left) - columns 9, 10 and 11 between them have no seat at all.
        for (final i in {8, 9, 10}) {
          expect(rowA.seats[i], isNull);
        }
      },
    );
  });

  group('parseWebticScreenIdFromOccupancy', () {
    test('reads idsala off a real Occupancy response, no ScreenId needed upfront', () {
      final raw = File(
        'test/fixtures/webtic_occupancy_sample.json',
      ).readAsStringSync();
      // Real Notorious Cagliari sample - see webtic_full_schedule_sample.json,
      // ScreenId 237 for that same performance's room.
      expect(parseWebticScreenIdFromOccupancy(raw), 237);
    });
  });

  group('parseWebticSeatMap (Cineplexx Bolzano - ACCOMPAGNATORE seats)', () {
    late WebticSeatMapPayload payload;

    setUpAll(() {
      payload = WebticSeatMapPayload(
        mapSeatsResponseBody: File(
          'test/fixtures/webtic_cineplexx_map_seats_sample.json',
        ).readAsStringSync(),
        occupancyResponseBody: File(
          'test/fixtures/webtic_cineplexx_occupancy_sample.json',
        ).readAsStringSync(),
      );
    });

    test(
      'an ACCOMPAGNATORE seat reads as accessibility on this chain too, not just Giometti',
      () {
        // Real Cineplexx Bolzano room (SALA 6, idsala 21): 11/1 and 11/2
        // are ACCOMPAGNATORE - user-reported doubt about disabled seats on
        // this specific chain prompted a live re-check, confirming the
        // same handling already added for Giometti carries over correctly.
        final seatMap = parseWebticSeatMap(payload);
        final seat = seatMap.rows
            .expand((r) => r.seats)
            .whereType<Seat>()
            .firstWhere((s) => s.name == '11/1');
        expect(seat.isAccessibility, isTrue);
      },
    );

    test(
      'the wheelchair spot in front of the ACCOMPAGNATORE seats is a real gap',
      () {
        // Row "11" (fila 13) only has seats from colonna 9 onward - columns
        // 5-8 are missing entirely (the wheelchair spaces themselves,
        // never listed in `posti`), same pattern as Giometti Pesaro.
        final seatMap = parseWebticSeatMap(payload);
        final row11 = seatMap.rows.firstWhere((r) => r.rowLabel == '11');
        for (final i in {4, 5, 6, 7}) {
          expect(row11.seats[i], isNull);
        }
      },
    );

    test('a STANDARD seat in the same "HC" settore is not accessibility', () {
      // The whole rear block of this room happens to share sector code
      // "HC" with the ACCOMPAGNATORE seats, but "HC" itself carries no
      // accessibility meaning - only individual seats with tipologia
      // ACCOMPAGNATORE/DISABILE do. Confirms accessibility is decided per
      // seat, never inferred from its sector.
      final seatMap = parseWebticSeatMap(payload);
      final seat = seatMap.rows
          .expand((r) => r.seats)
          .whereType<Seat>()
          .firstWhere((s) => s.name == '11/3');
      expect(seat.isAccessibility, isFalse);
    });
  });

  group('parseWebticProgrammingPage', () {
    late String raw;

    setUpAll(() {
      raw = File(
        'test/fixtures/webtic_giometti_programming_page_sample.html',
      ).readAsStringSync();
    });

    test('parses every film block, real Giometti Pesaro sample', () {
      final films = parseWebticProgrammingPage(
        raw,
        now: DateTime(2026, 7, 9),
      );
      expect(films, hasLength(12));
    });

    test('a film with several same-day showtimes, real sessions', () {
      final films = parseWebticProgrammingPage(
        raw,
        now: DateTime(2026, 7, 9),
      );
      final minions = films.firstWhere((f) => f.title == 'Minions & Monsters');
      expect(minions.day, DateTime(2026, 7, 9));
      expect(minions.sessions, hasLength(6));
      expect(
        minions.sessions.map((s) => s.time),
        containsAll(['17:30', '22:30']),
      );
    });

    test(
      'a film not showing today carries its own next playing day instead',
      () {
        final films = parseWebticProgrammingPage(
          raw,
          now: DateTime(2026, 7, 9),
        );
        final odissea = films.firstWhere((f) => f.title == 'Odissea');
        expect(odissea.day, DateTime(2026, 7, 16));
        final spiderMan = films.firstWhere(
          (f) => f.title == 'Spider-Man: Brand New Day',
        );
        expect(spiderMan.day, DateTime(2026, 7, 29));
      },
    );

    test('day/month with no year rolls over to next year near a year boundary', () {
      // A "02 Gennaio" listing found while checking in late December must
      // resolve to next January, not a January 65 weeks in the past.
      const html = '''
      <div class="wrap-scheda-programmazione-cinema">
        <h2>Capodanno Movie</h2>
        <div class="number">02</div><div class="month">Gennaio</div>
        <a href="x?ep=loadPerformance&sc=1&se=100&sp=200"><span class="orario">20:00</span>
      </div>
      ''';
      final films = parseWebticProgrammingPage(
        html,
        now: DateTime(2026, 12, 20),
      );
      expect(films.single.day, DateTime(2027, 1, 2));
    });
  });

  group('parseWebticFilmCatalog', () {
    late String raw;

    setUpAll(() {
      raw = File(
        'test/fixtures/webtic_cineplexx_home_sample.html',
      ).readAsStringSync();
    });

    test(
      'skips a film block missing a scheda link, real Cineplexx Bolzano homepage',
      () {
        // 11 "inprogrammazione" blocks on the real homepage, one of them
        // ("JACKASS: BEST AND LAST") has no /scheda/ link at all - real
        // platform quirk, not a parsing bug, so it's dropped rather than
        // crashing or emitting a film with no slug.
        final films = parseWebticFilmCatalog(raw, siteCinemaId: '2360');
        expect(films, hasLength(10));
        expect(films.any((f) => f.title.contains('JACKASS')), isFalse);
      },
    );

    test('a film missing entirely at this cinema is not in the result', () {
      // Confirmed live: not every film in the catalog plays at every
      // cinema - only films with a data-prog_{siteCinemaId} attribute do.
      final films = parseWebticFilmCatalog(raw, siteCinemaId: '999999');
      expect(films, isEmpty);
    });

    test('playing dates for one cinema, real MINIONS & MONSTERS sample', () {
      final films = parseWebticFilmCatalog(raw, siteCinemaId: '2360');
      final minions = films.firstWhere((f) => f.filmId == '47588');
      expect(minions.title, 'MINIONS & MONSTERS');
      expect(minions.slug, 'minions-monsters');
      expect(
        minions.playingDates,
        containsAll([DateTime(2026, 7, 9), DateTime(2026, 7, 15)]),
      );
    });
  });

  group('parseWebticFilmSchedulePage', () {
    test(
      'every day and showtime, real Cineplexx Bolzano MINIONS & MONSTERS sample',
      () {
        final raw = File(
          'test/fixtures/webtic_cineplexx_film_schedule_sample.html',
        ).readAsStringSync();
        final sessions = parseWebticFilmSchedulePage(
          raw,
          now: DateTime(2026, 7, 9),
        );
        // A real week (confirmed live: unlike Giometti, this page gives a
        // full week per film, not just one day).
        final days = sessions.map((s) => s.day).toSet();
        expect(days, hasLength(7));
        expect(days, contains(DateTime(2026, 7, 9)));

        final firstDay = sessions.where((s) => s.day == DateTime(2026, 7, 9));
        final threePm = firstDay.firstWhere((s) => s.performanceId == '226519');
        expect(threePm.time, '17:00');
        // Confirmed live: the LocalId embedded in each showtime's own link
        // (5098) differs from the site's own internal cinema id (2360)
        // used to build this very page's URL - never assume they match.
        expect(threePm.localId, 5098);
        expect(threePm.eventId, '7525');
      },
    );
  });
}
