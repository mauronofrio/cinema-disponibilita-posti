import 'dart:convert';

/// One film currently playing at a "Madison Cinemas" venue, as listed on its
/// `programmazione-...` page - just enough to identify it and then ask for
/// its *real* schedule (see [parseWebticMadisonFilmDays]): the page itself
/// only ever server-renders today's showtimes, but confirmed live that's a
/// limit of this one page, not of the platform - every film's own booking
/// widget can fetch a full week+ of other days via AJAX.
class ParsedMadisonCatalogFilm {
  const ParsedMadisonCatalogFilm({
    required this.filmId,
    required this.title,
    required this.posterUrl,
  });

  /// The `?film=` id from this film's own info page link - just an opaque
  /// identifier here (unlike Giometti's `eventId`, never needed to build a
  /// booking link: see [ParsedMadisonSession.performanceId]).
  final String filmId;
  final String title;
  final String? posterUrl;
}

/// One showtime, as returned by [parseWebticMadisonFilmDays].
class ParsedMadisonSession {
  const ParsedMadisonSession({
    required this.performanceId,
    required this.time,
    required this.screenName,
    required this.endTime,
  });

  final String performanceId;

  /// "HH:MM", parsed straight off the response - no date attached (that
  /// lives on the enclosing [ParsedMadisonDay.day] instead).
  final String time;

  /// The room name (e.g. "SALA 1 VENERI") - confirmed live in the real
  /// `giorno_by_film_cinema` response (`Screen`, same value duplicated as
  /// `ScreenName`), despite an earlier comment here claiming this was
  /// "never given by the response". [webtic_film_parser.dart] reads the
  /// same field name (`Screen`) off its own, differently-shaped Webtic
  /// response, so this follows that same convention rather than
  /// `ScreenName`.
  final String screenName;

  /// Also confirmed live in the same response (`EndTime`, a full ISO
  /// datetime) - same correction as [screenName] above.
  final DateTime endTime;
}

/// One calendar day's worth of showtimes for one film at one cinema, as
/// returned by the `giorno_by_film_cinema` WordPress AJAX action.
class ParsedMadisonDay {
  const ParsedMadisonDay({required this.day, required this.sessions});

  final DateTime day;
  final List<ParsedMadisonSession> sessions;
}

final _filmBlockSplitter = RegExp('class="col-md-6 box_film"');
final _posterRe = RegExp(r'<img src="([^"]+)" class="img-fluid" alt="[^"]*"');
final _titleFilmIdRe = RegExp(
  r'<h3><a href="/info-e-acquisto/\?film=(\d+)">([^<]*)</a></h3>',
);

/// Parses one "Madison Cinemas" venue's `programmazione-...` page just for
/// the film catalog it currently lists (title/poster/id) - the day and
/// showtime markup on this same page is deliberately ignored (see
/// [ParsedMadisonCatalogFilm] doc): the real per-day schedule for each of
/// these films comes from [parseWebticMadisonFilmDays] instead.
List<ParsedMadisonCatalogFilm> parseWebticMadisonProgrammingPage(String html) {
  final blocks = html.split(_filmBlockSplitter);
  final result = <ParsedMadisonCatalogFilm>[];
  final seenFilmIds = <String>{};
  for (final block in blocks.skip(1)) {
    final titleMatch = _titleFilmIdRe.firstMatch(block);
    if (titleMatch == null) continue;
    final filmId = titleMatch.group(1)!;
    if (!seenFilmIds.add(filmId)) continue;

    result.add(
      ParsedMadisonCatalogFilm(
        filmId: filmId,
        title: titleMatch.group(2)!.trim(),
        posterUrl: _posterRe.firstMatch(block)?.group(1),
      ),
    );
  }
  return result;
}

/// Parses a `giorno_by_film_cinema` AJAX response body - every day (each
/// with its own list of showtimes) one film is actually playing at one
/// cinema, confirmed live to cover a full week or more (e.g. 13 days for
/// some films at Cinema Madison - Roma), not just today. `performances` in
/// the raw JSON is itself a JSON-encoded string (double-encoded, not a
/// nested object) - decoded again here.
List<ParsedMadisonDay> parseWebticMadisonFilmDays(String responseBody) {
  final decoded = json.decode(responseBody) as Map<String, dynamic>;
  final items = decoded['items'] as List<dynamic>? ?? const [];

  return items.map((itemJson) {
    final item = itemJson as Map<String, dynamic>;
    final performances =
        json.decode(item['performances'] as String) as List<dynamic>;
    return ParsedMadisonDay(
      day: DateTime.parse(item['date'] as String),
      sessions: performances.map((p) {
        final performance = p as Map<String, dynamic>;
        return ParsedMadisonSession(
          performanceId: performance['PerformanceId'].toString(),
          time: performance['Time'] as String,
          screenName: (performance['Screen'] as String?) ?? '',
          endTime: DateTime.parse(performance['EndTime'] as String),
        );
      }).toList(),
    );
  }).toList();
}
