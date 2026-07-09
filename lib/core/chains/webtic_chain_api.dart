import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../date/clock.dart';
import '../models/cinema.dart';
import '../models/film.dart';
import '../models/seat_map.dart';
import '../models/showing_date.dart';
import '../network/webtic_platform_api_client.dart';
import 'chain_api.dart';
import 'webtic/webtic_film_parser.dart';
import 'webtic/webtic_programming_page_parser.dart';
import 'webtic/webtic_seat_map_parser.dart';

/// [ChainApi] for [CinemaChain.webtic]. Two different catalog sources exist
/// on this platform depending on [Cinema.webticScrapesProgrammingPage] (see
/// its own doc and PROJECT_NOTES.md):
/// - Notorious Cinemas: one [WebticPlatformApiClient.getFullSchedule] call
///   returns a cinema's entire catalog - every film, day and showtime - at
///   once.
/// - Giometti Cinema: no such call exists: [WebticPlatformApiClient
///   .getProgrammingPage] gives every film currently showing, but only ever
///   *one* calendar day's showtimes per film.
///
/// Neither is cached - both just fetch fresh every time, same "one-time
/// cost either way" tradeoff `UciChainApi` already makes for its own "fetch
/// everything, filter client-side" model.
///
/// Seat maps are identical either way: `getOccupancy` alone (just
/// `LocalId`+`PerformanceId`) always echoes back the real room id as
/// `idsala` (confirmed live on both chains), so [getSeatMap] never needs to
/// already know which room a showtime plays in - it calls `getOccupancy`
/// first and reads the room off its response, then calls `getMapSeats`.
class WebticChainApi implements ChainApi {
  WebticChainApi(this._client, this._clock);

  final WebticPlatformApiClient _client;
  final Clock _clock;

  @override
  Future<List<ShowingDate>> getShowingDates(Cinema cinema) async {
    if (cinema.webticScrapesProgrammingPage) {
      final html = await _client.getProgrammingPage(cinema.host!, cinema.slug);
      final films = parseWebticProgrammingPage(html, now: _clock.now());
      final days = films.map((f) => f.day).toSet().toList()..sort();
      return days.map((d) => ShowingDate(date: d, hasShowings: true)).toList();
    }
    final schedule = await _client.getFullSchedule(
      cinema.host!,
      cinema.webticLocalId!,
    );
    final days = parseWebticShowingDays(schedule);
    return days.map((d) => ShowingDate(date: d, hasShowings: true)).toList();
  }

  @override
  Future<List<Film>> getFilmsForDay(Cinema cinema, DateTime day) async {
    if (cinema.webticScrapesProgrammingPage) {
      return _getFilmsForDayFromProgrammingPage(cinema, day);
    }
    // [day] is unused - getFullSchedule already returns every day at once,
    // same reasoning as UciChainApi.getFilmsForDay (see ChainApi doc).
    final host = cinema.host!;
    final localId = cinema.webticLocalId!;
    final schedule = await _client.getFullSchedule(host, localId);
    final films = parseWebticFullSchedule(schedule);

    final result = <Film>[];
    for (final film in films) {
      if (film.sessionsByDay.isEmpty) continue;
      final showingGroups =
          film.sessionsByDay.entries.map((entry) {
              final sessions =
                  entry.value.map((parsed) {
                      return Session(
                        sessionId: parsed.performanceId,
                        startTime: parsed.startTime,
                        endTime: parsed.endTime,
                        screenName: parsed.screenName,
                        isSoldOut: false,
                        formattedPrice: null,
                        isPriceVisible: false,
                        attributes: const [],
                        // The chain's own quick-booking flow for this exact
                        // showtime (see PROJECT_NOTES.md) - this app never
                        // implements booking itself, it just hands off.
                        bookingPath:
                            'https://$host/generic/seatsframe.php'
                            '?sc=$localId&sp=${parsed.performanceId}'
                            '#seatsframe',
                      );
                    }).toList()
                    ..sort((a, b) => a.startTime.compareTo(b.startTime));
              return ShowingGroup(date: entry.key, sessions: sessions);
            }).toList()
            ..sort((a, b) => a.date.compareTo(b.date));

      result.add(
        Film(
          filmId: film.eventId,
          title: film.title,
          // The poster handler lives on the shared Webtic backend, not the
          // chain's own front-end site the rest of the catalog comes from
          // (confirmed live - see PROJECT_NOTES.md).
          posterImageSrc: film.posterPath == null
              ? null
              : 'https://secure.webtic.it/cvu/modules/${film.posterPath}',
          runningTime: film.runningTimeMinutes,
          showingGroups: showingGroups,
        ),
      );
    }
    result.sort((a, b) => a.title.compareTo(b.title));
    return result;
  }

  Future<List<Film>> _getFilmsForDayFromProgrammingPage(
    Cinema cinema,
    DateTime day,
  ) async {
    final host = cinema.host!;
    final localId = cinema.webticLocalId!;
    final html = await _client.getProgrammingPage(host, cinema.slug);
    final films = parseWebticProgrammingPage(html, now: _clock.now());

    final result = <Film>[];
    for (final film in films) {
      if (film.day.year != day.year ||
          film.day.month != day.month ||
          film.day.day != day.day) {
        continue;
      }
      final sessions =
          film.sessions.map((s) {
              final timeParts = s.time.split(':');
              final startTime = DateTime(
                film.day.year,
                film.day.month,
                film.day.day,
                int.parse(timeParts[0]),
                int.parse(timeParts[1]),
              );
              return Session(
                sessionId: s.performanceId,
                startTime: startTime,
                // The programmazione page never gives an end time.
                endTime: startTime,
                screenName: '',
                isSoldOut: false,
                formattedPrice: null,
                isPriceVisible: false,
                attributes: const [],
                bookingPath:
                    'https://$host/cinema/acquisti'
                    '?ep=loadPerformance&sc=$localId'
                    '&se=${film.eventId}&sp=${s.performanceId}',
              );
            }).toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));

      result.add(
        Film(
          filmId: film.eventId,
          title: film.title,
          posterImageSrc: film.posterUrl,
          runningTime: null,
          showingGroups: [ShowingGroup(date: film.day, sessions: sessions)],
        ),
      );
    }
    result.sort((a, b) => a.title.compareTo(b.title));
    return result;
  }

  @override
  Future<SeatMap> getSeatMap(Cinema cinema, Session session) async {
    final localId = cinema.webticLocalId!;
    final occupancyBody = await _client.getOccupancy(
      localId,
      session.sessionId,
    );
    final screenId = parseWebticScreenIdFromOccupancy(occupancyBody);
    final mapSeatsBody = await _client.getMapSeats(localId, screenId);
    return compute(
      parseWebticSeatMap,
      WebticSeatMapPayload(
        mapSeatsResponseBody: mapSeatsBody,
        occupancyResponseBody: occupancyBody,
      ),
    );
  }
}

final webticChainApiProvider = Provider<WebticChainApi>((ref) {
  return WebticChainApi(
    ref.watch(webticPlatformApiClientProvider),
    ref.watch(clockProvider),
  );
});
