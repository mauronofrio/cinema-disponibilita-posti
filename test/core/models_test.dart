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

    test(
      'webticCatalogSource defaults to fullSchedule when absent from the JSON',
      () {
        expect(
          Cinema.fromJson(baseJson()).webticCatalogSource,
          WebticCatalogSource.fullSchedule,
        );
      },
    );

    test('webticCatalogSource reads "programmingPage" for a Giometti-style cinema', () {
      final json = baseJson()..['webticCatalogSource'] = 'programmingPage';
      expect(
        Cinema.fromJson(json).webticCatalogSource,
        WebticCatalogSource.programmingPage,
      );
    });

    test('webticCatalogSource reads "filmSchedulePages" for a Cineplexx-style cinema', () {
      final json = baseJson()..['webticCatalogSource'] = 'filmSchedulePages';
      expect(
        Cinema.fromJson(json).webticCatalogSource,
        WebticCatalogSource.filmSchedulePages,
      );
    });

    test('webticCatalogSource reads "fullSchedulePortal" for a portal-wrapper cinema', () {
      final json = baseJson()..['webticCatalogSource'] = 'fullSchedulePortal';
      expect(
        Cinema.fromJson(json).webticCatalogSource,
        WebticCatalogSource.fullSchedulePortal,
      );
    });

    test('webticCatalogSource reads "madisonProgrammingPage" for a Madison Cinemas venue', () {
      final json = baseJson()..['webticCatalogSource'] = 'madisonProgrammingPage';
      expect(
        Cinema.fromJson(json).webticCatalogSource,
        WebticCatalogSource.madisonProgrammingPage,
      );
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
      expect(seatMap.totalRows, 3);
      expect(seatMap.totalColumns, 26);
    });

    test(
      'derives totalRows/totalColumns from the actual rows rather than '
      'seatingData - the live API stopped sending those fields entirely '
      '(confirmed on multiple The Space cinemas, seatingData now only ever '
      'has screenLabel), which used to crash parsing outright',
      () {
        final noTotalsJson = jsonEncode({
          'result': {
            'seatingData': {'screenLabel': 'Sala 1'},
            'seatRows': [
              {
                'rowLabel': 'A',
                'rowIndex': 1,
                'columns': [
                  {
                    'areaCategoryCode': 'PT',
                    'columnIndex': 1,
                    'rowIndex': 1,
                    'name': 'A1',
                    'seatStatus': 0,
                  },
                  null,
                  {
                    'areaCategoryCode': 'PT',
                    'columnIndex': 3,
                    'rowIndex': 1,
                    'name': 'A3',
                    'seatStatus': 0,
                  },
                ],
              },
            ],
            'areaCategories': [],
          },
        });
        final seatMap = SeatMap.fromApiResponseJson(noTotalsJson);
        expect(seatMap.totalRows, 1);
        expect(seatMap.totalColumns, 3);
      },
    );

    test(
      'a seat/row missing rowIndex, columnIndex or areaCategoryCode does not '
      'crash the parse - neither rowIndex/columnIndex is read anywhere in '
      "lib/features/ (the grid renders row.seats positionally, keyed off "
      'rowLabel), so they get the same safe-fallback treatment as every '
      'neighbouring field instead of a hard cast',
      () {
        final missingFieldsJson = jsonEncode({
          'result': {
            'seatingData': {'screenLabel': 'Sala 1'},
            'seatRows': [
              {
                'rowLabel': 'A',
                'columns': [
                  {
                    'name': 'A1',
                    'seatStatus': 0,
                  },
                ],
              },
            ],
            'areaCategories': [
              {'areaName': 'Platea', 'isSoldOut': false},
            ],
          },
        });
        final seatMap = SeatMap.fromApiResponseJson(missingFieldsJson);
        expect(seatMap.rows.single.rowIndex, 0);
        final seat = seatMap.rows.single.seats.single!;
        expect(seat.rowIndex, 0);
        expect(seat.columnIndex, 0);
        expect(seat.areaCategoryCode, '');
        expect(seatMap.areaCategories.single.code, '');
      },
    );

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
        final seatMap = SeatMap(
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

  group('groupSessionsByLanguage', () {
    Session makeSession(String id, {List<SessionAttribute> attributes = const []}) {
      return Session(
        sessionId: id,
        startTime: DateTime(2026, 9, 6, 18),
        endTime: DateTime(2026, 9, 6, 20),
        screenName: 'Sala 1',
        isSoldOut: false,
        formattedPrice: null,
        isPriceVisible: false,
        attributes: attributes,
        bookingPath: null,
      );
    }

    SessionAttribute language(String name) =>
        SessionAttribute(name: name, attributeType: 'Language', color: null);

    test(
      'a single language (or a chain that never reports one) collapses '
      'into one null-keyed group rather than splitting',
      () {
        final sessions = [makeSession('a'), makeSession('b')];
        final groups = groupSessionsByLanguage(sessions);
        expect(groups.keys, [null]);
        expect(groups[null], sessions);
      },
    );

    test(
      'this is the actual feature: ITALIANO and LINGUA ORIGINALE showings '
      'of the same film (e.g. Coyote vs Acme at The Space) split into '
      'separate groups, each keeping its own sessions in order',
      () {
        final ita1 = makeSession('ita1', attributes: [language('ITALIANO')]);
        final vo = makeSession(
          'vo',
          attributes: [language('LINGUA ORIGINALE')],
        );
        final ita2 = makeSession('ita2', attributes: [language('ITALIANO')]);

        final groups = groupSessionsByLanguage([ita1, vo, ita2]);

        expect(groups.keys, ['ITALIANO', 'LINGUA ORIGINALE']);
        expect(groups['ITALIANO'], [ita1, ita2]);
        expect(groups['LINGUA ORIGINALE'], [vo]);
      },
    );

    test(
      'a session with no Language attribute at all groups separately from '
      'ones that do, under the null key',
      () {
        final tagged = makeSession(
          'tagged',
          attributes: [language('ITALIANO')],
        );
        final untagged = makeSession('untagged');

        final groups = groupSessionsByLanguage([tagged, untagged]);

        expect(groups['ITALIANO'], [tagged]);
        expect(groups[null], [untagged]);
      },
    );
  });

  group('isNotableLanguage', () {
    test('null (no Language attribute at all) is not notable', () {
      expect(isNotableLanguage(null), isFalse);
    });

    test('the two known default-language spellings are not notable', () {
      expect(isNotableLanguage('ITALIANO'), isFalse);
      expect(isNotableLanguage('ITA'), isFalse);
    });

    test(
      'this is the actual regression case: a lone original-language '
      'showing with no dubbed alternative that day (e.g. UCI Seven Gioia '
      'del Colle\'s "Katy Perry: The Lifetimes Tour", ENG only, no ITA '
      'showing at all) is notable, so it still gets flagged',
      () {
        expect(isNotableLanguage('ENG'), isTrue);
        expect(isNotableLanguage('LINGUA ORIGINALE'), isTrue);
      },
    );
  });
}
