/// One showtime, as listed under a film's single day-block on a "Madison
/// Cinemas" `programmazione-...` page.
class ParsedMadisonSession {
  const ParsedMadisonSession({required this.performanceId, required this.time});

  final String performanceId;

  /// "HH:MM", parsed straight off the page - no date attached (that lives
  /// on the enclosing [ParsedMadisonFilm.day] instead).
  final String time;
}

/// One film block on the page - confirmed live (same as Giometti Cinema's
/// own `programmazione` page) to carry exactly *one* calendar day's worth of
/// showtimes, never a full week. Superficially the same platform limitation
/// as [ParsedGiomettiFilm] in `webtic_programming_page_parser.dart`, but a
/// completely different page template (WordPress theme, not the classic
/// `cvu/modules` front end) - different splitter, different booking-link
/// shape (`/info-e-acquisto/?performance={id}`, no `sc=`/`se=` params at
/// all), different day format (`Ddd DD/MM` in one `<p>`, not a
/// number-div/month-div pair) - so it gets its own parser rather than being
/// force-fit into the Giometti one.
class ParsedMadisonFilm {
  const ParsedMadisonFilm({
    required this.filmId,
    required this.title,
    required this.posterUrl,
    required this.day,
    required this.sessions,
  });

  /// The `?film=` id from this film's own info page link - just an opaque
  /// identifier here (unlike Giometti's `eventId`, never needed to build a
  /// booking link: see [ParsedMadisonSession.performanceId]).
  final String filmId;
  final String title;
  final String? posterUrl;
  final DateTime day;
  final List<ParsedMadisonSession> sessions;
}

final _filmBlockSplitter = RegExp('class="col-md-6 box_film"');
final _posterRe = RegExp(r'<img src="([^"]+)" class="img-fluid" alt="[^"]*"');
final _titleFilmIdRe = RegExp(
  r'<h3><a href="/info-e-acquisto/\?film=(\d+)">([^<]*)</a></h3>',
);
final _dayRe = RegExp(r'<p>\w+ (\d{2})/(\d{2})</p>');
final _orariRe = RegExp(
  r'/info-e-acquisto/\?performance=(\d+)#acquista_ora">(\d{2}):(\d{2})',
);

/// The page only ever prints a day/month, never a year - same reasoning and
/// approach as `webtic_programming_page_parser.dart`'s own `_inferYear`.
DateTime _inferYear(int day, int month, DateTime now) {
  var candidate = DateTime(now.year, month, day);
  if (candidate.isBefore(now.subtract(const Duration(days: 60)))) {
    candidate = DateTime(now.year + 1, month, day);
  }
  return candidate;
}

/// Parses one "Madison Cinemas" venue's `programmazione-...` page - every
/// film currently listed, each with the one day (and every showtime on it)
/// the page actually shows for it.
List<ParsedMadisonFilm> parseWebticMadisonProgrammingPage(
  String html, {
  required DateTime now,
}) {
  final blocks = html.split(_filmBlockSplitter);
  final result = <ParsedMadisonFilm>[];
  for (final block in blocks.skip(1)) {
    final titleMatch = _titleFilmIdRe.firstMatch(block);
    final dayMatch = _dayRe.firstMatch(block);
    if (titleMatch == null || dayMatch == null) continue;

    final orariMatches = _orariRe.allMatches(block).toList();
    if (orariMatches.isEmpty) continue;

    result.add(
      ParsedMadisonFilm(
        filmId: titleMatch.group(1)!,
        title: titleMatch.group(2)!.trim(),
        posterUrl: _posterRe.firstMatch(block)?.group(1),
        day: _inferYear(
          int.parse(dayMatch.group(1)!),
          int.parse(dayMatch.group(2)!),
          now,
        ),
        sessions: orariMatches
            .map(
              (m) => ParsedMadisonSession(
                performanceId: m.group(1)!,
                time: '${m.group(2)}:${m.group(3)}',
              ),
            )
            .toList(),
      ),
    );
  }
  return result;
}
