import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../date/clock.dart';
import '../models/cinema.dart';
import '../models/film.dart';
import '../models/seat_map.dart';
import '../models/showing_date.dart';
import '../network/eighteen_tickets_api_client.dart';
import '../util/ttl_cache.dart';
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
  _FilmPageSchedule({required this.catalogById, required this.sessionsById});

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
  EighteenTicketsChainApi(this._client, this._clock)
    : _filmPageSchedules = TtlCache(_clock, const Duration(minutes: 20));

  final EighteenTicketsApiClient _client;
  final Clock _clock;

  /// Keyed by [Cinema.cinemaId] - only ever populated for
  /// [Cinema.scheduleFromFilmPages] cinemas, everyone else's showtimes come
  /// straight from the (much cheaper) `fetch_films` response every time.
  final TtlCache<String, _FilmPageSchedule> _filmPageSchedules;

  /// One [Cinema.cinemaId]'s in-progress [_loadFilmPageSchedule] call, if
  /// any - see the dedup note in that method's own doc comment.
  final _inFlightSchedules = <String, Future<_FilmPageSchedule>>{};

  String _dateKey(DateTime day) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${day.year}-${two(day.month)}-${two(day.day)}';
  }

  @override
  Future<List<ShowingDate>> getShowingDates(Cinema cinema) {
    return runChainParsing(() async {
      if (cinema.scheduleFromFilmPages) {
        // fetch_films's own day picker still lists weeks of days here (it
        // only fails to render *showtimes*, see getFilmsForDay), but every
        // one of them would cost a full film-page-per-film fetch to actually
        // check - hardcoding to just today/tomorrow keeps that bounded.
        final today = _clock.now();
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
      var days = parseEighteenTicketsProgrammingDays(homepage);
      if (days.isEmpty) {
        // Confirmed live on a handful of tenants (e.g. Cinema Savoia -
        // Taranto): the day carousel isn't server-rendered into the bare
        // homepage at all there, only injected client-side via the same
        // XHR call `getFilmsForDay` already makes - whose response carries
        // the identical balloon markup. One extra request, only paid on
        // tenants where the homepage genuinely has nothing to parse.
        final today = _clock.now();
        final filmsForToday = await _client.getFilmsForDay(
          cinema.host!,
          _dateKey(today),
        );
        days = parseEighteenTicketsProgrammingDays(filmsForToday);
      }
      return days
          .map((d) => ShowingDate(date: DateTime.parse(d), hasShowings: true))
          .toList();
    });
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
  ///
  /// Two calls for different days (e.g. switching the today/tomorrow tab
  /// faster than a previous call finished) used to both read the same
  /// schedule before either had written anything back, so both went on to
  /// fetch the exact same per-film occupations for whatever films they had
  /// in common - on a platform documented above to 429 after only 4-5
  /// requests. [_inFlightSchedules] serializes calls per cinema instead: a
  /// call that finds one already running for this cinema waits for it to
  /// finish first, so it builds on whatever that call already fetched
  /// (via the shared, mutated-in-place [_FilmPageSchedule]) instead of
  /// duplicating it. A failure in the call being waited on is swallowed
  /// here, not inherited - this call still gets to make its own attempt
  /// below regardless of why the other one didn't finish cleanly.
  Future<_FilmPageSchedule> _loadFilmPageSchedule(
    Cinema cinema,
    DateTime day,
  ) async {
    final cinemaId = cinema.cinemaId;
    final inFlight = _inFlightSchedules[cinemaId];
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {
        // Swallowed deliberately - see doc comment above.
      }
    }
    final future = _loadFilmPageScheduleOnce(cinema, day);
    _inFlightSchedules[cinemaId] = future;
    try {
      return await future;
    } finally {
      // Only clear the slot if it's still this call's own future - a
      // waiting call that started its own fetch after this one finished
      // will have already replaced it with its own by the time this runs.
      if (identical(_inFlightSchedules[cinemaId], future)) {
        _inFlightSchedules.remove(cinemaId);
      }
    }
  }

  /// The actual fetch-and-merge work [_loadFilmPageSchedule] serializes per
  /// cinema - see that method's doc comment for why it's split out.
  Future<_FilmPageSchedule> _loadFilmPageScheduleOnce(
    Cinema cinema,
    DateTime day,
  ) async {
    final cached = _filmPageSchedules.get(cinema.cinemaId);
    final schedule =
        cached ?? _FilmPageSchedule(catalogById: {}, sessionsById: {});
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
    // Only stamp storedAt the first time this schedule is actually
    // created, not on every touch. TtlCache.set() resets the entry's
    // clock, so re-calling it here unconditionally - even when every film
    // in [catalog] was already in schedule.sessionsById and nothing new
    // was fetched at all - turned the 20-minute TTL into a sliding/idle
    // timeout: a user switching the today/tomorrow tab more often than
    // that kept the very first showtimes ever fetched alive for the whole
    // session, immune to a showtime added, moved or cancelled afterwards.
    // Mutating the already-cached schedule object in place (above, since
    // Dart maps/objects are shared by reference) already keeps whatever's
    // stored up to date with anything genuinely new - re-`set`ting on top
    // of that would only extend its life without reflecting a real
    // refresh.
    if (cached == null) {
      _filmPageSchedules.set(cinema.cinemaId, schedule);
    }
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
  Future<List<Film>> getFilmsForDay(Cinema cinema, DateTime day) {
    return runChainParsing(() async {
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
    });
  }

  @override
  Future<SeatMap> getSeatMap(Cinema cinema, Session session) {
    return runChainParsing(() async {
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
    });
  }
}

final eighteenTicketsChainApiProvider = Provider<EighteenTicketsChainApi>((
  ref,
) {
  return EighteenTicketsChainApi(
    ref.watch(eighteenTicketsApiClientProvider),
    ref.watch(clockProvider),
  );
});
