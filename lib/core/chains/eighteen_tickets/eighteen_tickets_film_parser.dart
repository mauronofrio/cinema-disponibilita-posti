/// Parsers for the "18tickets.net" platform's plain server-rendered HTML (no
/// JSON API - see PROJECT_NOTES.md). Shared by every independent cinema that
/// happens to run on this same platform (confirmed live: RedCarpet Cinema -
/// Monopoli and Multicinema Galleria - Bari are byte-for-byte compatible
/// with the same regexes, different venues on the same booking backend, not
/// a chain in the branding sense). Regex-based rather than a full HTML DOM
/// parser: every element this needs to read is a single, consistently-quoted
/// tag with a fixed (alphabetical) attribute order, so targeted patterns are
/// simpler and just as reliable here as a general parser would be.
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

/// Matches a closing tag's `/`, which - like quotes (see [_q]) - shows up
/// as a literal backslash-then-slash (`<\/a>`) on the AJAX fragment
/// endpoints instead of a plain `</a>` (a common JS-string-escaping
/// convention: escape `/` whenever it follows `<`, so an embedded `</script>`
/// can never prematurely close the surrounding real `<script>` tag).
String _close(String tagName) => "<\\\\?/$tagName>";

/// The AJAX fragment endpoints also encode every real newline as a literal
/// backslash-then-`n` (JS string escaping, same root cause as [_q]/[_close])
/// rather than an actual newline character - so a plain `\s` never matches
/// it. Un-escaping it back into a real newline up front means every other
/// pattern here can just use ordinary `\s` and get whitespace-tolerant
/// behaviour "for free", instead of every single one needing its own
/// `(?:\s|\\n)` alternation.
String _normalizeEscapedNewlines(String html) => html.replaceAll('\\n', '\n');

String _decodeHtmlEntities(String input) {
  return input
      .replaceAll('&amp;', '&')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}

/// One film as listed for a given day - metadata only, no showtimes (those
/// are the sibling `sessions` list in [EighteenTicketsDayProgramming]).
class EighteenTicketsFilmSummary {
  const EighteenTicketsFilmSummary({
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
  "movie__title$_q\\s+href=${_q}https?://[^/'\"]+/film/(\\d+)[^'\"]*$_q>\\s*([^<]+?)\\s*${_close('a')}",
);
final _posterRe = RegExp(
  "<img[^>]*class=$_q[^'\"]*img-thumbnail[^'\"]*$_q[^>]*src=$_q([^'\"\\\\]+)$_q",
);

final _dayBalloonRe = RegExp(
  "class=${_q}m18-day-elem select-date[^'\"]*$_q\\s+data-target=$_q(\\d{4}-\\d{2}-\\d{2})$_q",
);

/// Every day the date-picker offers, from either the homepage or a
/// `fetch_films` response - both carry the same balloon carousel.
List<String> parseEighteenTicketsProgrammingDays(String html) {
  final normalized = _normalizeEscapedNewlines(html);
  return _dayBalloonRe.allMatches(normalized).map((m) => m.group(1)!).toList();
}

/// One showtime for one film, on the one day
/// [parseEighteenTicketsFilmsForDay] was called for.
class ParsedEighteenTicketsSession {
  const ParsedEighteenTicketsSession({
    required this.filmId,
    required this.sessionId,
    required this.theaterName,
    required this.startTime,
  });

  final String filmId;
  final String sessionId;
  final String theaterName;
  final DateTime startTime;
}

/// A day's full film list *and* every film's showtimes that day, together -
/// see PROJECT_NOTES.md: `GET /film/fetch_films?date=...` embeds both, so
/// one request per day covers every film, unlike the naive "one request per
/// film per day" approach it replaced (which got the app rate-limited once a
/// cinema had ~20 films to check).
class EighteenTicketsDayProgramming {
  const EighteenTicketsDayProgramming({
    required this.films,
    required this.sessions,
  });

  final List<EighteenTicketsFilmSummary> films;
  final List<ParsedEighteenTicketsSession> sessions;
}

final _sessionAnchorRe = RegExp(
  "<a data-time=$_q\\d+$_q\\s+href=${_q}https?://[^/'\"]+/film/\\d+/([a-f0-9-]+)#theater-init$_q>([\\s\\S]*?)${_close('a')}",
);
final _timeRoomRe = RegExp(r"(\d{2}):(\d{2})\s*<br\s*/?>\s*([^<]+)");

/// Parses a `GET /film/fetch_films?date=YYYY-MM-DD` response. [date] is the
/// same date requested - the response's own showtimes only ever carry a
/// bare `HH:MM`, no date, so the caller's request date is trusted rather
/// than re-parsed from a "Mercoledì 08/07/2026"-style label in the markup.
EighteenTicketsDayProgramming parseEighteenTicketsFilmsForDay(
  String html,
  DateTime date,
) {
  final blocks = _normalizeEscapedNewlines(html).split(_filmBlockSplitter);
  final films = <EighteenTicketsFilmSummary>[];
  final sessions = <ParsedEighteenTicketsSession>[];
  final seenIds = <String>{};
  for (final block in blocks.skip(1)) {
    final linkMatch = _filmLinkRe.firstMatch(block);
    if (linkMatch == null) continue;
    final filmId = linkMatch.group(1)!;
    if (seenIds.add(filmId)) {
      final posterMatch = _posterRe.firstMatch(block);
      films.add(
        EighteenTicketsFilmSummary(
          filmId: filmId,
          title: _decodeHtmlEntities(linkMatch.group(2)!.trim()),
          posterUrl: posterMatch?.group(1),
        ),
      );
    }
    for (final anchorMatch in _sessionAnchorRe.allMatches(block)) {
      final sessionId = anchorMatch.group(1)!;
      final timeRoom = _timeRoomRe.firstMatch(anchorMatch.group(2)!);
      if (timeRoom == null) continue;
      sessions.add(
        ParsedEighteenTicketsSession(
          filmId: filmId,
          sessionId: sessionId,
          theaterName: timeRoom.group(3)!.trim(),
          startTime: DateTime(
            date.year,
            date.month,
            date.day,
            int.parse(timeRoom.group(1)!),
            int.parse(timeRoom.group(2)!),
          ),
        ),
      );
    }
  }
  return EighteenTicketsDayProgramming(films: films, sessions: sessions);
}

final _projectionTagRe = RegExp("<a class=${_q}film-projection[^>]*>");

String? _attr(String tag, String name) {
  // The value capture excludes a literal backslash too, not just the quote
  // characters - on the AJAX-fragment responses the closing delimiter is
  // itself `\'` (backslash then quote), and without this a greedy `[^'"]*`
  // swallows that backslash as if it were part of the value.
  final match = RegExp("$name=$_q([^'\"\\\\]*)$_q").firstMatch(tag);
  return match?.group(1);
}

/// The room a specific session plays in, read off its own `/film/{filmId}/
/// {sessionId}` page. Not known upfront (unlike The Space/UCI, this
/// platform's `fetch_films` response gives every session id but never its
/// room's own uuid, only the room's display name) - resolved lazily, only
/// when the user actually opens that session's seat map (see
/// `EighteenTicketsChainApi`). A film's own page can list several of its
/// showtimes at once, each potentially in a different room, so this matches
/// the one `film-projection` tag whose own `data-id` is [sessionId] rather
/// than assuming the first one found on the page is the right one.
String? parseEighteenTicketsTheaterIdForSession(
  String filmPageHtml,
  String sessionId,
) {
  for (final match in _projectionTagRe.allMatches(filmPageHtml)) {
    final tag = match.group(0)!;
    if (_attr(tag, 'data-id') == sessionId) {
      return _attr(tag, 'data-theater');
    }
  }
  return null;
}
