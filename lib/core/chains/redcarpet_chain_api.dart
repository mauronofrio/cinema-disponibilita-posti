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
///
/// This site's server enforces a surprisingly aggressive per-IP rate limit -
/// confirmed live that even plain *sequential* requests (no concurrency
/// involved) start getting HTTP 429 ("Slow down! Too many requests") after
/// only about 4-5 total requests in a short window, recovering roughly a
/// minute later. That's what makes [getFilmsForDay] genuinely lazy here
/// (unlike The Space/UCI, which fetch every day up front because it's
/// cheap for them): only the one day a caller actually asks for is ever
/// fetched, never pre-loaded for days nobody's looking at yet.
class RedCarpetChainApi implements ChainApi {
  RedCarpetChainApi(this._client);

  final RedCarpetApiClient _client;

  String _dateKey(DateTime day) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${day.year}-${two(day.month)}-${two(day.day)}';
  }

  @override
  Future<List<ShowingDate>> getShowingDates(Cinema cinema) async {
    // Just the homepage - the day picker itself lists a full month or more
    // (23+ days observed live) at no extra cost, since it's baked into the
    // one page load. Only fetching a specific day's *films* (below) has a
    // real per-request cost, so there's no reason to trim this list.
    final homepage = await _client.getHomepage(cinema.host!);
    final days = parseRedCarpetProgrammingDays(homepage);
    return days
        .map((d) => ShowingDate(date: DateTime.parse(d), hasShowings: true))
        .toList();
  }

  @override
  Future<List<Film>> getFilmsForDay(Cinema cinema, DateTime day) async {
    final host = cinema.host!;
    final html = await _client.getFilmsForDay(host, _dateKey(day));
    final programming = parseRedCarpetFilmsForDay(html, day);

    final sessionsByFilm = <String, List<ParsedRedCarpetSession>>{};
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
                    bookingPath: null,
                    redCarpetFilmId: film.filmId,
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
