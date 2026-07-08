import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cinema.dart';
import '../models/film.dart';
import '../models/seat_map.dart';
import '../models/showing_date.dart';
import '../network/eighteen_tickets_api_client.dart';
import 'chain_api.dart';
import 'eighteen_tickets/eighteen_tickets_film_parser.dart';
import 'eighteen_tickets/eighteen_tickets_seat_map_parser.dart';

/// One [Cinema.scheduleFromFilmPages] cinema's showtimes, read off one
/// `fetch_film_occupations` request *per film* (every date that film has,
/// all at once - see `EighteenTicketsApiClient.getAllFilmOccupations`) -
/// accumulated by [EighteenTicketsChainApi] across both the "today" and
/// "tomorrow" day tabs, so a film already fetched from either day's catalog
/// is never re-fetched just because the other day's catalog lists it too
/// (see the class doc for why that matters on this platform).
class _FilmPageSchedule {
  _FilmPageSchedule({
    required this.fetchedAt,
    required this.catalogById,
    required this.sessionsById,
  });

  final DateTime fetchedAt;

  /// The catalog entry (title/poster) for every film seen so far, across
  /// however many days' catalogs have actually been fetched.
  final Map<String, EighteenTicketsFilmSummary> catalogById;

  /// Every real showtime for each film, across every date it has (not just
  /// whichever day it was first discovered from) - filtered down to one
  /// specific day only when building that day's [Film] list. A film's
  /// presence as a key here (regardless of how many sessions it maps to)
  /// is also what marks it as already fetched, so it's never requested
  /// twice.
  final Map<String, List<ParsedEighteenTicketsSession>> sessionsById;
}

/// [ChainApi] for the "18tickets.net" platform - shared by every small,
/// independent cinema built on it (not a chain in the branding sense: each
/// one is its own venue with its own `Cinema.host`, confirmed live that
/// RedCarpet Cinema - Monopoli and Multicinema Galleria - Bari are
/// byte-for-byte compatible with the same parsing code). See
/// PROJECT_NOTES.md: no JSON API here, everything is scraped from plain
/// server-rendered HTML/SVG.
///
/// This platform's servers enforce a surprisingly aggressive per-IP rate
/// limit - confirmed live that even plain *sequential* requests (no
/// concurrency involved) start getting HTTP 429 ("Slow down! Too many
/// requests") after only about 4-5 total requests in a short window,
/// recovering roughly a minute later. That's what makes [getFilmsForDay]
/// genuinely lazy here (unlike The Space/UCI, which fetch every day up
/// front because it's cheap for them): only the one day a caller actually
/// asks for is ever fetched, never pre-loaded for days nobody's looking at
/// yet.
class EighteenTicketsChainApi implements ChainApi {
  EighteenTicketsChainApi(this._client);

  final EighteenTicketsApiClient _client;

  /// Keyed by [Cinema.cinemaId] - only ever populated for
  /// [Cinema.scheduleFromFilmPages] cinemas, everyone else's showtimes come
  /// straight from the (much cheaper) `fetch_films` response every time.
  final _filmPageSchedules = <String, _FilmPageSchedule>{};

  String _dateKey(DateTime day) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${day.year}-${two(day.month)}-${two(day.day)}';
  }

  @override
  Future<List<ShowingDate>> getShowingDates(Cinema cinema) async {
    if (cinema.scheduleFromFilmPages) {
      // fetch_films's own day picker still lists weeks of days here (it
      // only fails to render *showtimes*, see getFilmsForDay), but every one
      // of them would cost a full film-page-per-film fetch to actually
      // check - hardcoding to just today/tomorrow keeps that bounded.
      final today = DateTime.now();
      final tomorrow = today.add(const Duration(days: 1));
      return [
        ShowingDate(
          date: DateTime(today.year, today.month, today.day),
          hasShowings: true,
        ),
        ShowingDate(
          date: DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
          hasShowings: true,
        ),
      ];
    }
    // Just the homepage - the day picker itself lists a full month or more
    // (23+ days observed live) at no extra cost, since it's baked into the
    // one page load. Only fetching a specific day's *films* (below) has a
    // real per-request cost, so there's no reason to trim this list.
    final homepage = await _client.getHomepage(cinema.host!);
    final days = parseEighteenTicketsProgrammingDays(homepage);
    return days
        .map((d) => ShowingDate(date: DateTime.parse(d), hasShowings: true))
        .toList();
  }

  /// [Cinema.scheduleFromFilmPages] cinemas only - see the field doc and
  /// [_FilmPageSchedule]. `fetch_films` is still used, just for the film
  /// catalog (titles/posters), which does render correctly there - fetched
  /// fresh for whichever [day] is actually asked for rather than always
  /// "today", since today's and tomorrow's catalogs don't necessarily list
  /// the same films (confirmed live on Multisala Massimo: 3 films only
  /// showed up in tomorrow's catalog, never today's). Every catalog film not
  /// already in [_FilmPageSchedule.sessionsById] then gets exactly one
  /// `fetch_film_occupations` request, covering every date it has at once -
  /// a film discovered from today's catalog is never fetched again just
  /// because tomorrow's catalog lists it too. A real delay between those
  /// requests is deliberate: this platform starts returning 429 after only
  /// about 4-5 sequential requests in a short window (see the class doc) -
  /// confirmed live that even 600ms between requests wasn't enough, 2.5s
  /// reliably was, at the cost of a slower first load per cache window
  /// (masked by the 20-minute cache after that).
  Future<_FilmPageSchedule> _loadFilmPageSchedule(
    Cinema cinema,
    DateTime day,
  ) async {
    var schedule = _filmPageSchedules[cinema.cinemaId];
    if (schedule == null ||
        DateTime.now().difference(schedule.fetchedAt) >=
            const Duration(minutes: 20)) {
      schedule = _FilmPageSchedule(
        fetchedAt: DateTime.now(),
        catalogById: {},
        sessionsById: {},
      );
    }
    final host = cinema.host!;
    final catalogHtml = await _client.getFilmsForDay(host, _dateKey(day));
    final catalog = parseEighteenTicketsFilmsForDay(catalogHtml, day).films;

    for (final film in catalog) {
      schedule.catalogById[film.filmId] = film;
      if (schedule.sessionsById.containsKey(film.filmId)) continue;
      await Future.delayed(const Duration(milliseconds: 2500));
      final occupationsHtml = await _client.getAllFilmOccupations(
        host,
        film.filmId,
      );
      schedule.sessionsById[film.filmId] = parseEighteenTicketsAllSessionsForFilm(
        occupationsHtml,
        film.filmId,
      );
    }
    _filmPageSchedules[cinema.cinemaId] = schedule;
    return schedule;
  }

  Future<List<Film>> _getFilmsForDayFromFilmPages(
    Cinema cinema,
    DateTime day,
  ) async {
    final host = cinema.host!;
    final schedule = await _loadFilmPageSchedule(cinema, day);
    final dayKey = _dateKey(day);

    final result = <Film>[];
    for (final MapEntry(key: filmId, value: film) in schedule
        .catalogById
        .entries) {
      final sessionsThatDay = (schedule.sessionsById[filmId] ?? const [])
          .where((s) => _dateKey(s.startTime) == dayKey)
          .toList();
      if (sessionsThatDay.isEmpty) continue;
      result.add(
        Film(
          filmId: filmId,
          title: film.title,
          posterImageSrc: film.posterUrl,
          runningTime: null,
          showingGroups: [
            ShowingGroup(
              date: DateTime(day.year, day.month, day.day),
              sessions:
                  sessionsThatDay
                      .map(
                        (parsed) => Session(
                          sessionId: parsed.sessionId,
                          startTime: parsed.startTime,
                          endTime: parsed.startTime,
                          screenName: parsed.theaterName,
                          isSoldOut: false,
                          formattedPrice: null,
                          isPriceVisible: false,
                          attributes: const [],
                          bookingPath:
                              'https://$host/film/$filmId/${parsed.sessionId}#theater-init',
                          eighteenTicketsFilmId: filmId,
                        ),
                      )
                      .toList()
                    ..sort((a, b) => a.startTime.compareTo(b.startTime)),
            ),
          ],
        ),
      );
    }
    result.sort((a, b) => a.title.compareTo(b.title));
    return result;
  }

  @override
  Future<List<Film>> getFilmsForDay(Cinema cinema, DateTime day) async {
    if (cinema.scheduleFromFilmPages) {
      return _getFilmsForDayFromFilmPages(cinema, day);
    }
    final host = cinema.host!;
    final html = await _client.getFilmsForDay(host, _dateKey(day));
    final programming = parseEighteenTicketsFilmsForDay(html, day);

    final sessionsByFilm = <String, List<ParsedEighteenTicketsSession>>{};
    for (final session in programming.sessions) {
      sessionsByFilm.putIfAbsent(session.filmId, () => []).add(session);
    }

    final result = <Film>[];
    for (final film in programming.films) {
      final sessions = sessionsByFilm[film.filmId];
      if (sessions == null || sessions.isEmpty) continue;
      final showingGroup = ShowingGroup(
        date: DateTime(day.year, day.month, day.day),
        sessions:
            sessions
                .map(
                  (parsed) => Session(
                    sessionId: parsed.sessionId,
                    startTime: parsed.startTime,
                    // fetch_films never gives an end time - not shown
                    // anywhere sessions are rendered, so an estimate is fine.
                    endTime: parsed.startTime,
                    screenName: parsed.theaterName,
                    isSoldOut: false,
                    formattedPrice: null,
                    isPriceVisible: false,
                    attributes: const [],
                    // The one page this platform has for a single showtime
                    // (also where getSeatMap reads the room id from, see
                    // above) is itself the booking flow - the same
                    // `fetch_films` markup links here as "Programmazione
                    // Completa"/the time chip's own href.
                    bookingPath:
                        'https://$host/film/${film.filmId}/${parsed.sessionId}#theater-init',
                    eighteenTicketsFilmId: film.filmId,
                  ),
                )
                .toList()
              ..sort((a, b) => a.startTime.compareTo(b.startTime)),
      );
      result.add(
        Film(
          filmId: film.filmId,
          title: film.title,
          posterImageSrc: film.posterUrl,
          runningTime: null,
          showingGroups: [showingGroup],
        ),
      );
    }
    result.sort((a, b) => a.title.compareTo(b.title));
    return result;
  }

  @override
  Future<SeatMap> getSeatMap(Cinema cinema, Session session) async {
    final host = cinema.host!;
    final filmId = session.eighteenTicketsFilmId!;
    // The room a showtime plays in isn't known upfront on this platform -
    // only its own page exposes it (see eighteen_tickets_film_parser.dart).
    final filmPage = await _client.getFilmSessionPage(
      host,
      filmId,
      session.sessionId,
    );
    final theaterId = parseEighteenTicketsTheaterIdForSession(
      filmPage,
      session.sessionId,
    )!;
    final results = await Future.wait([
      _client.getTheaterSvg(host, theaterId),
      _client.getSeatOccupancy(host, session.sessionId),
    ]);
    return compute(
      parseEighteenTicketsSeatMap,
      EighteenTicketsSeatMapPayload(
        theaterSvg: results[0],
        occupancyJson: results[1],
      ),
    );
  }
}

final eighteenTicketsChainApiProvider = Provider<EighteenTicketsChainApi>((
  ref,
) {
  return EighteenTicketsChainApi(ref.watch(eighteenTicketsApiClientProvider));
});
