/// One showtime, as listed under a film's single day-block on the
/// "programmazione" page.
class ParsedGiomettiSession {
  const ParsedGiomettiSession({required this.performanceId, required this.time});

  final String performanceId;

  /// "HH:MM", parsed straight off the page - no date attached (that lives
  /// on the enclosing [ParsedGiomettiFilm.day] instead).
  final String time;
}

/// One film block on the page - confirmed live to carry exactly *one*
/// calendar day's worth of showtimes (today's, or the next day it's
/// actually playing if not today - e.g. an upcoming release) rather than a
/// full week the way Notorious Cinemas' `getFullSched` does. See
/// PROJECT_NOTES.md for why this is a real platform limitation, not a
/// parsing shortcut: the page itself never renders more than this.
class ParsedGiomettiFilm {
  const ParsedGiomettiFilm({
    required this.eventId,
    required this.title,
    required this.posterUrl,
    required this.day,
    required this.sessions,
  });

  final String eventId;
  final String title;
  final String? posterUrl;
  final DateTime day;
  final List<ParsedGiomettiSession> sessions;
}

final _filmBlockSplitter = RegExp('wrap-scheda-programmazione-cinema');
final _posterRe = RegExp(r'<img src="([^"]+)" alt="[^"]*"');
final _titleRe = RegExp(r'<h2>([^<]*)</h2>');
final _dayRe = RegExp(
  r'<div class="number">(\d+)</div><div class="month">([^<]+)</div>',
);
final _orariRe = RegExp(
  r'ep=loadPerformance&sc=\d+&se=(\d+)&sp=(\d+)"><span class="orario">(\d{2}):(\d{2})',
);

const _italianMonths = {
  'gennaio': 1,
  'febbraio': 2,
  'marzo': 3,
  'aprile': 4,
  'maggio': 5,
  'giugno': 6,
  'luglio': 7,
  'agosto': 8,
  'settembre': 9,
  'ottobre': 10,
  'novembre': 11,
  'dicembre': 12,
};

/// The page only ever prints a day/month, never a year - inferred against
/// [now] rather than always assuming the current year, so a listing near a
/// year boundary (e.g. checking a "02 Gennaio" listing in late December)
/// still resolves to the right calendar year.
DateTime _inferYear(int day, int month, DateTime now) {
  var candidate = DateTime(now.year, month, day);
  if (candidate.isBefore(now.subtract(const Duration(days: 60)))) {
    candidate = DateTime(now.year + 1, month, day);
  }
  return candidate;
}

/// Parses one cinema's `programmazione` page - every film currently listed,
/// each with the one day (and every showtime on it) the page actually shows
/// for it. [now] is injected for the day/month-only year inference above,
/// same reasoning as every other clock-dependent parser in this codebase.
List<ParsedGiomettiFilm> parseWebticProgrammingPage(
  String html, {
  required DateTime now,
}) {
  final blocks = html.split(_filmBlockSplitter);
  final result = <ParsedGiomettiFilm>[];
  for (final block in blocks.skip(1)) {
    final titleMatch = _titleRe.firstMatch(block);
    final dayMatch = _dayRe.firstMatch(block);
    if (titleMatch == null || dayMatch == null) continue;

    final month = _italianMonths[dayMatch.group(2)!.trim().toLowerCase()];
    if (month == null) continue;

    final orariMatches = _orariRe.allMatches(block).toList();
    if (orariMatches.isEmpty) continue;

    result.add(
      ParsedGiomettiFilm(
        eventId: orariMatches.first.group(1)!,
        title: titleMatch.group(1)!.trim(),
        posterUrl: _posterRe.firstMatch(block)?.group(1),
        day: _inferYear(int.parse(dayMatch.group(1)!), month, now),
        sessions: orariMatches
            .map(
              (m) => ParsedGiomettiSession(
                performanceId: m.group(2)!,
                time: '${m.group(3)}:${m.group(4)}',
              ),
            )
            .toList(),
      ),
    );
  }
  return result;
}
