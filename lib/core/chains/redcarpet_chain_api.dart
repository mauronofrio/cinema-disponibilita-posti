import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cinema.dart';
import '../models/film.dart';
import '../models/seat_map.dart';
import '../models/showing_date.dart';
import '../network/redcarpet_api_client.dart';
import 'chain_api.dart';
import 'redcarpet/redcarpet_film_parser.dart';
import 'redcarpet/redcarpet_seat_map_parser.dart';

/// [ChainApi] for RedCarpet Cinema - a small independent cinema (not a
/// multi-location chain) on the "18tickets.net" platform. See
/// PROJECT_NOTES.md: no JSON API here, everything is scraped from plain
/// server-rendered HTML/SVG.
class RedCarpetChainApi implements ChainApi {
  RedCarpetChainApi(this._client);

  final RedCarpetApiClient _client;

  /// RedCarpet's own day picker offers a full month or more (23+ days
  /// observed live), but this site's server enforces a hard per-IP rate
  /// limit that's much tighter than expected: confirmed live that even
  /// plain *sequential* requests (no concurrency involved) start getting
  /// HTTP 429 ("Slow down! Too many requests") after only about 4-5 total
  /// requests in a short window (well under a minute), recovering roughly
  /// a minute later. `getFilmsForDay` being one request per day (rather
  /// than one per film per day) doesn't help here - the limiter counts
  /// total requests, not per-film load - so this has to stay small
  /// regardless of how cheap each individual request is. Kept deliberately
  /// conservative (with the one homepage request that always precedes it,
  /// this totals 4 requests per "open this cinema" action, at the edge of
  /// what was confirmed to work reliably).
  static const _maxDays = 3;

  List<String> _limitedDays(String homepage) {
    final days = parseRedCarpetProgrammingDays(homepage);
    return days.length <= _maxDays ? days : days.sublist(0, _maxDays);
  }

  /// Runs [action] over every item with at most [concurrency] in flight at
  /// once, and lets any individual failure just drop that one item instead
  /// of aborting the whole batch.
  Future<void> _forEachBounded<T>(
    List<T> items,
    int concurrency,
    Future<void> Function(T item) action,
  ) async {
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        final item = items[next++];
        try {
          await action(item);
        } catch (_) {
          // Skip this one day; the rest of the batch still has value even
          // if a handful of requests fail.
        }
      }
    }

    await Future.wait(
      List.generate(
        concurrency.clamp(1, items.isEmpty ? 1 : items.length),
        (_) => worker(),
      ),
    );
  }

  @override
  Future<List<ShowingDate>> getShowingDates(Cinema cinema) async {
    final homepage = await _client.getHomepage(cinema.host!);
    final days = _limitedDays(homepage);
    return days
        .map((d) => ShowingDate(date: DateTime.parse(d), hasShowings: true))
        .toList();
  }

  @override
  Future<List<Film>> getFilmsForCinema(Cinema cinema) async {
    final host = cinema.host!;
    final homepage = await _client.getHomepage(host);
    final days = _limitedDays(homepage);

    // One request per *day* - `fetch_films` embeds every film's own
    // metadata and that day's showtimes in the same response (see
    // PROJECT_NOTES.md; this replaced an earlier "one request per film per
    // day" design that got the app rate-limited on this small site once a
    // cinema had ~20 films to check).
    final filmsById = <String, RedCarpetFilmSummary>{};
    final sessionsByFilm = <String, List<ParsedRedCarpetSession>>{};
    await _forEachBounded(days, 3, (day) async {
      final html = await _client.getFilmsForDay(host, day);
      final programming = parseRedCarpetFilmsForDay(html, DateTime.parse(day));
      for (final film in programming.films) {
        filmsById.putIfAbsent(film.filmId, () => film);
      }
      for (final session in programming.sessions) {
        sessionsByFilm.putIfAbsent(session.filmId, () => []).add(session);
      }
    });

    final result = <Film>[];
    for (final film in filmsById.values) {
      final sessions = sessionsByFilm[film.filmId];
      if (sessions == null || sessions.isEmpty) continue;
      final byDay = <DateTime, List<Session>>{};
      for (final parsed in sessions) {
        final day = DateTime(
          parsed.startTime.year,
          parsed.startTime.month,
          parsed.startTime.day,
        );
        byDay
            .putIfAbsent(day, () => [])
            .add(
              Session(
                sessionId: parsed.sessionId,
                startTime: parsed.startTime,
                // fetch_films never gives an end time - not shown anywhere
                // sessions are rendered, so an estimate is fine.
                endTime: parsed.startTime,
                screenName: parsed.theaterName,
                isSoldOut: false,
                formattedPrice: null,
                isPriceVisible: false,
                attributes: const [],
                bookingPath: null,
                redCarpetFilmId: film.filmId,
              ),
            );
      }
      final showingGroups =
          byDay.entries
              .map(
                (e) => ShowingGroup(
                  date: e.key,
                  sessions: e.value
                    ..sort((a, b) => a.startTime.compareTo(b.startTime)),
                ),
              )
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
      result.add(
        Film(
          filmId: film.filmId,
          title: film.title,
          posterImageSrc: film.posterUrl,
          runningTime: null,
          showingGroups: showingGroups,
        ),
      );
    }
    result.sort((a, b) => a.title.compareTo(b.title));
    return result;
  }

  @override
  Future<SeatMap> getSeatMap(Cinema cinema, Session session) async {
    final host = cinema.host!;
    final filmId = session.redCarpetFilmId!;
    // The room a showtime plays in isn't known upfront on this platform -
    // only its own page exposes it (see redcarpet_film_parser.dart).
    final filmPage = await _client.getFilmSessionPage(
      host,
      filmId,
      session.sessionId,
    );
    final theaterId = parseRedCarpetTheaterIdForSession(
      filmPage,
      session.sessionId,
    )!;
    final results = await Future.wait([
      _client.getTheaterSvg(host, theaterId),
      _client.getSeatOccupancy(host, session.sessionId),
    ]);
    return compute(
      parseRedCarpetSeatMap,
      RedCarpetSeatMapPayload(
        theaterSvg: results[0],
        occupancyJson: results[1],
      ),
    );
  }
}

final redCarpetChainApiProvider = Provider<RedCarpetChainApi>((ref) {
  return RedCarpetChainApi(ref.watch(redCarpetApiClientProvider));
});
