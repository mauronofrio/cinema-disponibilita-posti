/// Parsers for RedCarpet's plain server-rendered HTML (no JSON API - see
/// PROJECT_NOTES.md). Regex-based rather than a full HTML DOM parser: every
/// element this needs to read is a single, consistently-quoted tag with a
/// fixed (alphabetical) attribute order, so targeted patterns are simpler
/// and just as reliable here as a general parser would be.
///
/// Quote handling has two wrinkles: plain page loads use double quotes,
/// while the AJAX fragment endpoints (`fetch_films`/`fetch_film_occupations`)
/// return their markup as a jQuery `.html('...')` *string literal*, where
/// single quotes appear as a literal backslash followed by a quote (`\'`) -
/// not real HTML attribute syntax. [_q] (an optional literal backslash,
/// then either quote character) matches both.
///
/// Patterns below are built from plain (non-raw) strings so `_q` can be
/// interpolated in - every literal backslash needed for the regex itself is
/// written doubled (`\\`) accordingly.
library;

const _q = "\\\\?['\"]";

String _decodeHtmlEntities(String input) {
  return input
      .replaceAll('&amp;', '&')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}

/// One film as listed on the cinema's homepage - metadata only, no
/// showtimes (those come from [parseRedCarpetFilmOccupations] instead).
class RedCarpetFilmSummary {
  const RedCarpetFilmSummary({
    required this.filmId,
    required this.title,
    required this.posterUrl,
  });

  final String filmId;
  final String title;
  final String? posterUrl;
}

final _filmBlockSplitter = RegExp("movie\\s+movie--preview");
final _filmLinkRe = RegExp(
  "movie__title$_q\\s+href=${_q}https?://[^/'\"]+/film/(\\d+)[^'\"]*$_q>\\s*([^<]+?)\\s*</a>",
);
final _posterRe = RegExp(
  "<img[^>]*class=$_q[^'\"]*img-thumbnail[^'\"]*$_q[^>]*src=$_q([^'\"\\\\]+)$_q",
);

/// Splits the homepage on each `.movie--preview` card and pulls out the one
/// title/id/poster from each - there's always at least a title link before
/// any poster `<img>` in the same block, so limiting each regex to its own
/// slice (up to the next block) avoids ever matching into a neighbour.
List<RedCarpetFilmSummary> parseRedCarpetFilmList(String homepageHtml) {
  final blocks = homepageHtml.split(_filmBlockSplitter);
  final films = <RedCarpetFilmSummary>[];
  final seenIds = <String>{};
  for (final block in blocks.skip(1)) {
    final linkMatch = _filmLinkRe.firstMatch(block);
    if (linkMatch == null) continue;
    final filmId = linkMatch.group(1)!;
    if (!seenIds.add(filmId)) {
      continue; // the title/poster link repeats within the same block
    }
    final posterMatch = _posterRe.firstMatch(block);
    films.add(
      RedCarpetFilmSummary(
        filmId: filmId,
        title: _decodeHtmlEntities(linkMatch.group(2)!.trim()),
        posterUrl: posterMatch?.group(1),
      ),
    );
  }
  return films;
}

final _dayBalloonRe = RegExp(
  "class=${_q}m18-day-elem select-date[^'\"]*$_q\\s+data-target=$_q(\\d{4}-\\d{2}-\\d{2})$_q",
);

/// Every day the date-picker offers, from either the homepage or a film
/// page - both carry the same balloon carousel.
List<String> parseRedCarpetProgrammingDays(String html) {
  return _dayBalloonRe.allMatches(html).map((m) => m.group(1)!).toList();
}

/// One showtime for one film, on the one day [parseRedCarpetFilmOccupations]
/// was called for.
class ParsedRedCarpetSession {
  const ParsedRedCarpetSession({
    required this.sessionId,
    required this.theaterId,
    required this.theaterName,
    required this.startTime,
  });

  final String sessionId;
  final String theaterId;
  final String theaterName;
  final DateTime startTime;
}

final _projectionTagRe = RegExp("<a class=${_q}film-projection[^>]*>");
final _dateTimeRe = RegExp(r"(\d{2})/(\d{2})/(\d{4}) ore (\d{2}):(\d{2})");

String? _attr(String tag, String name) {
  // The value capture excludes a literal backslash too, not just the quote
  // characters - on the AJAX-fragment responses the closing delimiter is
  // itself `\'` (backslash then quote), and without this a greedy `[^'"]*`
  // swallows that backslash as if it were part of the value.
  final match = RegExp("$name=$_q([^'\"\\\\]*)$_q").firstMatch(tag);
  return match?.group(1);
}

/// Parses a `GET /film/{filmId}/fetch_film_occupations?date=...` response
/// (or the same `<a class='film-projection'>` markup embedded in a plain
/// film page) into one entry per showtime that day.
List<ParsedRedCarpetSession> parseRedCarpetFilmOccupations(String html) {
  final sessions = <ParsedRedCarpetSession>[];
  for (final tagMatch in _projectionTagRe.allMatches(html)) {
    final tag = tagMatch.group(0)!;
    final id = _attr(tag, 'data-id');
    final theaterId = _attr(tag, 'data-theater');
    final theaterName = _attr(tag, 'data-theater-name');
    final dateExtended = _attr(tag, 'data-date-extended');
    if (id == null || theaterId == null || dateExtended == null) continue;
    final dt = _dateTimeRe.firstMatch(dateExtended);
    if (dt == null) continue;
    sessions.add(
      ParsedRedCarpetSession(
        sessionId: id,
        theaterId: theaterId,
        theaterName: theaterName ?? '',
        startTime: DateTime(
          int.parse(dt.group(3)!),
          int.parse(dt.group(2)!),
          int.parse(dt.group(1)!),
          int.parse(dt.group(4)!),
          int.parse(dt.group(5)!),
        ),
      ),
    );
  }
  return sessions;
}
