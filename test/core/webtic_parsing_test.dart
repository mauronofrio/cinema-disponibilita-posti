import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/chains/webtic/webtic_film_parser.dart';
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
}
