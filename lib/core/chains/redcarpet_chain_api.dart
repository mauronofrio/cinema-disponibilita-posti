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
  /// observed live, sometimes with a gap where nothing's scheduled yet) -
  /// with no bulk endpoint, showing every film's sessions for every one of
  /// those days would mean one request per film *per day*, easily 400+
  /// requests for a single "open this cinema" action. Confirmed live: that
  /// volume alone is enough to get rate-limited (HTTP 429, "Slow down! Too
  /// many requests") by this small site's server, on top of just being an
  /// unreasonable amount of load to put on it. Both [getShowingDates] and
  /// [getFilmsForCinema] cap themselves to the same near window instead -
  /// same days offered as fetched, so a day chip is never shown "empty"
  /// just because it was never actually asked for.
  static const _maxDays = 5;

  List<String> _limitedDays(String homepage) {
    final days = parseRedCarpetProgrammingDays(homepage);
    return days.length <= _maxDays ? days : days.sublist(0, _maxDays);
  }

  /// Runs [action] over every item with at most [concurrency] in flight at
  /// once, and lets any individual failure just drop that one item instead
  /// of aborting the whole batch. Both matter for [getFilmsForCinema]: it
  /// has no bulk endpoint at all, so a whole cinema's film list means one
  /// request per film per day - dozens to a couple hundred requests, enough
  /// that firing them all at once (a plain `Future.wait`) was observed live
  /// to make some of them time out, and without per-item error isolation a
  /// single flaky one used to take the entire film list down with it.
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
          // Skip this one film+day combination; the rest of the batch
          // still has value even if a handful of requests fail.
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
    final films = parseRedCarpetFilmList(homepage);
    final days = _limitedDays(homepage);

    // One request per film per day - RedCarpet has no bulk endpoint at all
    // (not even UCI's "one call per day for every film"). Even capped to
    // _maxDays this can be dozens of requests, so still worth the bounded
    // concurrency (see _forEachBounded) rather than firing them all at
    // once: observed live to make some requests time out otherwise.
    final sessionsByFilm = <String, List<ParsedRedCarpetSession>>{};
    final pairs = films
        .expand((film) => days.map((day) => (film, day)))
        .toList();
    await _forEachBounded(pairs, 6, (pair) async {
      final (film, day) = pair;
      final html = await _client.getFilmOccupations(host, film.filmId, day);
      final sessions = parseRedCarpetFilmOccupations(html);
      if (sessions.isEmpty) return;
      sessionsByFilm.putIfAbsent(film.filmId, () => []).addAll(sessions);
    });

    final result = <Film>[];
    for (final film in films) {
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
                // The occupations feed never gives an end time - not shown
                // anywhere sessions are rendered, so an estimate is fine.
                endTime: parsed.startTime,
                screenName: parsed.theaterName,
                isSoldOut: false,
                formattedPrice: null,
                isPriceVisible: false,
                attributes: const [],
                bookingPath: null,
                redCarpetTheaterId: parsed.theaterId,
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
    final theaterId = session.redCarpetTheaterId!;
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
