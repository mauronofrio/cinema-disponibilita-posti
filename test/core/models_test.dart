import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/models/cinema.dart';
import 'package:thespace_companion/core/models/film.dart';
import 'package:thespace_companion/core/models/seat_map.dart';

void main() {
  group('Cinema.fromJson', () {
    Map<String, dynamic> baseJson() => {
      'cinemaId': 'x',
      'name': 'X',
      'slug': 'x',
      'address': 'Via X 1, Città',
      'lat': 0.0,
      'lng': 0.0,
      'chain': 'eighteenTickets',
    };

    test('hasSeatMap defaults to true when absent from the JSON', () {
      expect(Cinema.fromJson(baseJson()).hasSeatMap, isTrue);
    });

    test('hasSeatMap reads false for a programme-only cinema', () {
      final json = baseJson()..['hasSeatMap'] = false;
      expect(Cinema.fromJson(json).hasSeatMap, isFalse);
    });

    test('scheduleFromFilmPages defaults to false when absent from the JSON', () {
      expect(Cinema.fromJson(baseJson()).scheduleFromFilmPages, isFalse);
    });

    test('scheduleFromFilmPages reads true for a broken-calendar cinema', () {
      final json = baseJson()..['scheduleFromFilmPages'] = true;
      expect(Cinema.fromJson(json).scheduleFromFilmPages, isTrue);
    });

    test('chain "webtic" parses to CinemaChain.webtic', () {
      final json = baseJson()..['chain'] = 'webtic';
      expect(Cinema.fromJson(json).chain, CinemaChain.webtic);
    });

    test('webticLocalId round-trips for a webtic-chain cinema', () {
      final json = baseJson()
        ..['chain'] = 'webtic'
        ..['webticLocalId'] = 5631;
      expect(Cinema.fromJson(json).webticLocalId, 5631);
    });
  });

  group('SeatMap.fromApiResponseJson', () {
    late String rawJson;

    setUpAll(() {
      rawJson = File('test/fixtures/seats_sample.json').readAsStringSync();
    });

    test('parses screen metadata', () {
      final seatMap = SeatMap.fromApiResponseJson(rawJson);
      expect(seatMap.screenLabel, 'Sala 5');
      expect(seatMap.totalRows, 19);
      expect(seatMap.totalColumns, 26);
    });

    test('maps every known seatStatus code to the right enum value', () {
      final seatMap = SeatMap.fromApiResponseJson(rawJson);
      final byStatus = <SeatStatus, int>{};
      for (final row in seatMap.rows) {
        for (final seat in row.seats) {
          if (seat == null) continue;
          byStatus[seat.status] = (byStatus[seat.status] ?? 0) + 1;
        }
      }
      // The fixture was curated to cover codes 0, 1, 9 and 11.
      expect(byStatus[SeatStatus.available], greaterThan(0));
      expect(byStatus[SeatStatus.occupied], greaterThan(0));
      expect(byStatus[SeatStatus.accessibility], greaterThan(0));
    });

    test('unknown seatStatus codes fall back to unknown, not a crash', () {
      expect(seatStatusFromCode(999), SeatStatus.unknown);
    });

    test(
      'preserves the raw column array order rather than reordering by columnIndex',
      () {
        // The reference implementation (github.com/mauronofrio/TheSpace_Fast_Seat_Check,
        // validated against the real site) trusts the API's array order as-is.
        // The fixture's row A has columnIndex descending (20, 19, ..., 5) in
        // raw array order, so the first element must still be the seat named
        // "A20" - not reordered to array position 20.
        final decoded = json.decode(rawJson) as Map<String, dynamic>;
        final rawRowA = (decoded['result']['seatRows'] as List<dynamic>)
            .firstWhere((r) => r['rowLabel'] == 'A');
        final rawFirstSeatName = (rawRowA['columns'] as List<dynamic>)
            .firstWhere((c) => c != null)['name'];
        expect(rawFirstSeatName, 'A20');

        final seatMap = SeatMap.fromApiResponseJson(rawJson);
        final rowA = seatMap.rows.firstWhere((r) => r.rowLabel == 'A');
        expect(rowA.seats.firstWhere((s) => s != null)?.name, 'A20');
      },
    );

    test(
      'preserves the raw seatRows array order rather than sorting by rowIndex',
      () {
        final decoded = json.decode(rawJson) as Map<String, dynamic>;
        final rawLabels = (decoded['result']['seatRows'] as List<dynamic>)
            .map((r) => r['rowLabel'])
            .toList();

        final seatMap = SeatMap.fromApiResponseJson(rawJson);
        expect(seatMap.rows.map((r) => r.rowLabel).toList(), rawLabels);
      },
    );

    test('drops the redundant per-seat sitecoreSeatStatus payload', () {
      final decoded = json.decode(rawJson) as Map<String, dynamic>;
      final firstRowWithSeat = (decoded['result']['seatRows'] as List<dynamic>)
          .firstWhere(
            (r) => (r['columns'] as List<dynamic>).any((c) => c != null),
          );
      final rawSeat = (firstRowWithSeat['columns'] as List<dynamic>).firstWhere(
        (c) => c != null,
      );
      expect(
        rawSeat,
        contains('sitecoreSeatStatus'),
        reason: 'sanity check: fixture still has the bloat',
      );

      final seatMap = SeatMap.fromApiResponseJson(rawJson);
      final firstSeat = seatMap.rows
          .expand((r) => r.seats)
          .firstWhere((s) => s != null)!;
      // Seat only exposes the trimmed fields - nothing to assert "absence" of
      // sitecoreSeatStatus on since the model has no such field at all.
      expect(firstSeat.name, isNotEmpty);
      expect(firstSeat.areaCategoryCode, isNotEmpty);
    });

    test('parses area categories with color and sold-out flag', () {
      final seatMap = SeatMap.fromApiResponseJson(rawJson);
      expect(seatMap.areaCategories, isNotEmpty);
      final category = seatMap.areaCategories.first;
      expect(category.code, isNotEmpty);
      expect(category.color, startsWith('#'));
    });

    test(
      'occupancy counters match a manual count, excluding accessibility seats, '
      'and never double-count aisle gaps',
      () {
        final seatMap = SeatMap.fromApiResponseJson(rawJson);
        // Accessibility seats are deliberately left out of both counters -
        // see SeatMap.totalSeatCount - so the manual count here must match
        // that, not every seat in the room.
        final countedSeats = seatMap.rows
            .expand((r) => r.seats)
            .whereType<Seat>()
            .where((s) => !s.isAccessibility)
            .toList();

        expect(seatMap.totalSeatCount, countedSeats.length);
        expect(
          seatMap.availableSeatCount,
          countedSeats.where((s) => s.status == SeatStatus.available).length,
        );
        expect(
          seatMap.occupiedSeatCount,
          seatMap.totalSeatCount - seatMap.availableSeatCount,
        );
        expect(
          seatMap.occupancyRatio,
          seatMap.occupiedSeatCount / seatMap.totalSeatCount,
        );
      },
    );

    test(
      'SeatStatus.special seats are excluded from both counters, like accessibility seats',
      () {
        // A SeatStatus.special seat is never actually bookable regardless of
        // chain (confirmed live on an 18tickets room where a whole
        // upper-gallery section is permanently marked this way) - without
        // this exclusion it would always count as "occupied"
        // (totalSeatCount - availableSeatCount), making a room using it
        // look far busier than it really is even when genuinely empty.
        const seatMap = SeatMap(
          screenLabel: '',
          totalRows: 1,
          totalColumns: 3,
          areaCategories: [],
          rows: [
            SeatRow(
              rowLabel: 'A',
              rowIndex: 1,
              seats: [
                Seat(
                  rowIndex: 1,
                  columnIndex: 1,
                  name: 'A1',
                  status: SeatStatus.available,
                  areaCategoryCode: 'PT',
                ),
                Seat(
                  rowIndex: 1,
                  columnIndex: 2,
                  name: 'A2',
                  status: SeatStatus.occupied,
                  areaCategoryCode: 'PT',
                ),
                Seat(
                  rowIndex: 1,
                  columnIndex: 3,
                  name: 'A3',
                  status: SeatStatus.special,
                  areaCategoryCode: 'PT',
                ),
              ],
            ),
          ],
        );
        expect(seatMap.totalSeatCount, 2);
        expect(seatMap.availableSeatCount, 1);
        expect(seatMap.occupiedSeatCount, 1);
      },
    );
  });

  group('Film parsing', () {
    late List<dynamic> rawFilms;

    setUpAll(() {
      final decoded = json.decode(
        File('test/fixtures/films_sample.json').readAsStringSync(),
      );
      rawFilms = decoded['result'] as List<dynamic>;
    });

    test('maps title, poster and showing groups', () {
      final film = Film.fromJson(rawFilms.first as Map<String, dynamic>);
      expect(film.title, isNotEmpty);
      expect(film.filmId, isNotEmpty);
      expect(film.showingGroups, isNotEmpty);
    });

    test('sessionsOn returns sessions only for the matching calendar day', () {
      final film = Film.fromJson(rawFilms.first as Map<String, dynamic>);
      final firstGroupDate = film.showingGroups.first.date;

      expect(film.sessionsOn(firstGroupDate), isNotEmpty);
      expect(
        film.sessionsOn(firstGroupDate.add(const Duration(days: 365))),
        isEmpty,
      );
    });

    test(
      'drops empty-name session attributes (API includes blank placeholders)',
      () {
        final film = Film.fromJson(rawFilms.first as Map<String, dynamic>);
        final session = film.showingGroups.first.sessions.first;
        expect(session.attributes.every((a) => a.name.isNotEmpty), isTrue);
      },
    );
  });
}
