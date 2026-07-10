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
import 'webtic/webtic_film_schedule_page_parser.dart';
import 'webtic/webtic_madison_programming_page_parser.dart';
import 'webtic/webtic_programming_page_parser.dart';
import 'webtic/webtic_seat_map_parser.dart';

/// [ChainApi] for [CinemaChain.webtic]. Three different catalog sources
/// exist on this platform depending on [Cinema.webticCatalogSource] (see
/// [WebticCatalogSource]'s own doc and PROJECT_NOTES.md for how each was
/// discovered) - none of them cached, all just fetched fresh every time,
/// same "one-time cost either way" tradeoff `UciChainApi` already makes for
/// its own "fetch everything, filter client-side" model.
///
/// Seat maps are identical across all three sources though: `getOccupancy`
/// alone (just `LocalId`+`PerformanceId`) always echoes back the real room
/// id as `idsala` (confirmed live on every chain checked), so [getSeatMap]
/// never needs to already know which room a showtime plays in - it calls
/// `getOccupancy` first and reads the room off its response, then calls
/// `getMapSeats`.
class WebticChainApi implements ChainApi {
  WebticChainApi(this._client, this._clock);

  final WebticPlatformApiClient _client;
  final Clock _clock;

  @override
  Future<List<ShowingDate>> getShowingDates(Cinema cinema) async {
    switch (cinema.webticCatalogSource) {
      case WebticCatalogSource.programmingPage:
        final html = await _client.getProgrammingPage(
          cinema.host!,
          cinema.slug,
        );
        final films = parseWebticProgrammingPage(html, now: _clock.now());
        final days = films.map((f) => f.day).toSet().toList()..sort();
        return days
            .map((d) => ShowingDate(date: d, hasShowings: true))
            .toList();

      case WebticCatalogSource.filmSchedulePages:
        final html = await _client.getFilmCatalogHomepage(cinema.host!);
        final catalog = parseWebticFilmCatalog(
          html,
          siteCinemaId: cinema.slug,
        );
        final days = <DateTime>{};
        for (final film in catalog) {
          days.addAll(film.playingDates);
        }
        final sortedDays = days.toList()..sort();
        return sortedDays
            .map((d) => ShowingDate(date: d, hasShowings: true))
            .toList();

      case WebticCatalogSource.fullSchedule:
        final schedule = await _client.getFullSchedule(
          cinema.host!,
          cinema.webticLocalId!,
        );
        final days = parseWebticShowingDays(schedule);
        return days
            .map((d) => ShowingDate(date: d, hasShowings: true))
            .toList();

      case WebticCatalogSource.fullSchedulePortal:
        final schedule = await _client.getFullScheduleViaPortal(
          cinema.webticLocalId!,
        );
        final days = parseWebticShowingDays(schedule);
        return days
            .map((d) => ShowingDate(date: d, hasShowings: true))
            .toList();

      case WebticCatalogSource.madisonProgrammingPage:
        final catalog = await _madisonCatalogFilmDays(cinema);
        final days = <DateTime>{};
        for (final filmDays in catalog.values) {
          days.addAll(filmDays.map((d) => d.day));
        }
        final sortedDays = days.toList()..sort();
        return sortedDays
            .map((d) => ShowingDate(date: d, hasShowings: true))
            .toList();
    }
  }

  // One `giorno_by_film_cinema` call per film currently listed on the venue's
  // programmazione page - same "one request per film" cost already accepted
  // for [WebticCatalogSource.filmSchedulePages], and for the same reason:
  // the catalog page alone only ever shows today, the real multi-day
  // schedule only exists per film (confirmed live - see PROJECT_NOTES.md).
  // Fired concurrently (`Future.wait`), not one after another - a venue
  // with 15 films awaiting each call in turn is noticeably slow to load
  // (confirmed live on Cinema Madison - Roma) for no benefit, since none of
  // these per-film requests depend on each other.
  Future<Map<ParsedMadisonCatalogFilm, List<ParsedMadisonDay>>>
  _madisonCatalogFilmDays(Cinema cinema) async {
    final host = cinema.host!;
    final localId = cinema.webticLocalId!;
    final html = await _client.getMadisonProgrammingPage(host, cinema.slug);
    final catalog = parseWebticMadisonProgrammingPage(html);

    final allDays = await Future.wait(
      catalog.map(
        (film) => _client.getMadisonFilmDays(host, localId, film.filmId),
      ),
    );
    return Map.fromIterables(
      catalog,
      allDays.map(parseWebticMadisonFilmDays),
    );
  }

  @override
  Future<List<Film>> getFilmsForDay(Cinema cinema, DateTime day) async {
    switch (cinema.webticCatalogSource) {
      case WebticCatalogSource.programmingPage:
        return _getFilmsForDayFromProgrammingPage(cinema, day);
      case WebticCatalogSource.filmSchedulePages:
        return _getFilmsForDayFromFilmSchedulePages(cinema, day);
      case WebticCatalogSource.fullSchedule:
        return _getFilmsForDayFromFullSchedule(cinema);
      case WebticCatalogSource.fullSchedulePortal:
        return _getFilmsForDayFromFullSchedulePortal(cinema);
      case WebticCatalogSource.madisonProgrammingPage:
        return _getFilmsForDayFromMadisonProgrammingPage(cinema, day);
    }
  }

  // [day] is unused - getFullSchedule already returns every day at once,
  // same reasoning as UciChainApi.getFilmsForDay (see ChainApi doc).
  Future<List<Film>> _getFilmsForDayFromFullSchedule(Cinema cinema) async {
    final host = cinema.host!;
    final localId = cinema.webticLocalId!;
    final schedule = await _client.getFullSchedule(host, localId);
    return _filmsFromFullScheduleBody(
      schedule,
      bookingPathFor: (performanceId) =>
          'https://$host/generic/seatsframe.php'
          '?sc=$localId&sp=$performanceId'
          '#seatsframe',
    );
  }

  // Same response shape as [_getFilmsForDayFromFullSchedule] - see
  // [WebticCatalogSource.fullSchedulePortal] - just a different fetch and a
  // generic hand-off link, since these venues' own sites don't expose a
  // per-performance booking path the way the classic `cvu/modules` front
  // end does.
  Future<List<Film>> _getFilmsForDayFromFullSchedulePortal(
    Cinema cinema,
  ) async {
    final localId = cinema.webticLocalId!;
    final schedule = await _client.getFullScheduleViaPortal(localId);
    return _filmsFromFullScheduleBody(
      schedule,
      bookingPathFor: (_) =>
          'https://www.webtic.it/index.htm#/home?action=loadLocal&localId=$localId',
    );
  }

  List<Film> _filmsFromFullScheduleBody(
    String schedule, {
    required String Function(String performanceId) bookingPathFor,
  }) {
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
                        bookingPath: bookingPathFor(parsed.performanceId),
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

  Future<List<Film>> _getFilmsForDayFromMadisonProgrammingPage(
    Cinema cinema,
    DateTime day,
  ) async {
    final host = cinema.host!;
    final catalog = await _madisonCatalogFilmDays(cinema);

    final result = <Film>[];
    for (final entry in catalog.entries) {
      final film = entry.key;
      final matchingDay = entry.value.where(
        (d) =>
            d.day.year == day.year &&
            d.day.month == day.month &&
            d.day.day == day.day,
      );
      if (matchingDay.isEmpty) continue;

      final sessions =
          matchingDay.first.sessions.map((s) {
              final timeParts = s.time.split(':');
              final startTime = DateTime(
                day.year,
                day.month,
                day.day,
                int.parse(timeParts[0]),
                int.parse(timeParts[1]),
              );
              return Session(
                sessionId: s.performanceId,
                startTime: startTime,
                // Never given by the response.
                endTime: startTime,
                screenName: '',
                isSoldOut: false,
                formattedPrice: null,
                isPriceVisible: false,
                attributes: const [],
                // No `sc=`/`se=` params needed here - unlike Giometti's own
                // booking path, this chain's site resolves everything from
                // the performance id alone (confirmed live).
                bookingPath:
                    'https://$host/info-e-acquisto/'
                    '?performance=${s.performanceId}#acquista_ora',
              );
            }).toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));

      result.add(
        Film(
          filmId: film.filmId,
          title: film.title,
          posterImageSrc: film.posterUrl,
          runningTime: null,
          showingGroups: [ShowingGroup(date: day, sessions: sessions)],
        ),
      );
    }
    result.sort((a, b) => a.title.compareTo(b.title));
    return result;
  }

  Future<List<Film>> _getFilmsForDayFromFilmSchedulePages(
    Cinema cinema,
    DateTime day,
  ) async {
    final host = cinema.host!;
    final siteCinemaId = cinema.slug;
    final catalogHtml = await _client.getFilmCatalogHomepage(host);
    final catalog = parseWebticFilmCatalog(
      catalogHtml,
      siteCinemaId: siteCinemaId,
    );

    // Only films the homepage already says play at this cinema on this
    // exact day are worth a whole extra request each for - the rest can
    // never contribute a session for [day] anyway.
    final playingToday = catalog.where(
      (f) => f.playingDates.any(
        (d) => d.year == day.year && d.month == day.month && d.day == day.day,
      ),
    );

    final result = <Film>[];
    for (final film in playingToday) {
      final scheduleHtml = await _client.getFilmSchedulePage(
        host,
        film.slug,
        film.filmId,
        siteCinemaId,
      );
      final sessions = parseWebticFilmSchedulePage(
        scheduleHtml,
        now: _clock.now(),
      ).where(
        (s) =>
            s.day.year == day.year &&
            s.day.month == day.month &&
            s.day.day == day.day,
      );
      if (sessions.isEmpty) continue;

      final sessionObjs =
          sessions.map((s) {
              final timeParts = s.time.split(':');
              final startTime = DateTime(
                day.year,
                day.month,
                day.day,
                int.parse(timeParts[0]),
                int.parse(timeParts[1]),
              );
              return Session(
                sessionId: s.performanceId,
                startTime: startTime,
                // The schedule page never gives an end time.
                endTime: startTime,
                screenName: '',
                isSoldOut: false,
                formattedPrice: null,
                isPriceVisible: false,
                attributes: const [],
                bookingPath:
                    'https://$host/acquista/${film.slug}'
                    '/${s.localId}/${s.eventId}/${s.performanceId}/',
              );
            }).toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));

      result.add(
        Film(
          filmId: film.filmId,
          title: film.title,
          posterImageSrc: film.posterUrl,
          runningTime: null,
          showingGroups: [ShowingGroup(date: day, sessions: sessionObjs)],
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
