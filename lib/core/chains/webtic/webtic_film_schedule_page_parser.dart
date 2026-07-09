/// One film's catalog entry, as read off the chain's own homepage - which
/// of the chain's cinemas show it (identified by [Cinema.slug], the
/// site-internal numeric id, not [Cinema.webticLocalId]) already embedded
/// there, but not the individual showtimes themselves (see
/// [ParsedCineplexxSession], read from a separate per-film page).
class ParsedCineplexxCatalogFilm {
  const ParsedCineplexxCatalogFilm({
    required this.filmId,
    required this.slug,
    required this.title,
    required this.posterUrl,
    required this.playingDates,
  });

  final String filmId;
  final String slug;
  final String title;
  final String? posterUrl;

  /// Every calendar day this film has at least one showtime on, at the one
  /// cinema (`siteCinemaId`) [parseWebticFilmCatalog] was called for.
  final List<DateTime> playingDates;
}

final _catalogBlockSplitter = RegExp('class="inprogrammazione"');
final _catalogIdFilmRe = RegExp(r'data-idfilm="(\d+)"');
final _catalogTitleRe = RegExp(r'data-title="([^"]*)"');
final _catalogSlugRe = RegExp(r'href="/scheda/([a-z0-9-]+)/\d+/"');
final _catalogPosterRe = RegExp(r'<img src="([^"]+)"');

/// Parses the chain's own homepage into every film currently in its
/// catalog that's showing at [siteCinemaId] (that cinema's own numeric id
/// on this site, `Cinema.slug`) - a film missing a `data-prog_{id}`
/// attribute for this id isn't showing there at all and is skipped.
List<ParsedCineplexxCatalogFilm> parseWebticFilmCatalog(
  String html, {
  required String siteCinemaId,
}) {
  final progDateRe = RegExp('data-prog_$siteCinemaId="([^"]*)"');
  final blocks = html.split(_catalogBlockSplitter);
  final result = <ParsedCineplexxCatalogFilm>[];
  for (final block in blocks.skip(1)) {
    final progMatch = progDateRe.firstMatch(block);
    if (progMatch == null) continue;

    final idFilmMatch = _catalogIdFilmRe.firstMatch(block);
    final titleMatch = _catalogTitleRe.firstMatch(block);
    final slugMatch = _catalogSlugRe.firstMatch(block);
    if (idFilmMatch == null || titleMatch == null || slugMatch == null) {
      continue;
    }

    result.add(
      ParsedCineplexxCatalogFilm(
        filmId: idFilmMatch.group(1)!,
        slug: slugMatch.group(1)!,
        title: titleMatch.group(1)!,
        posterUrl: _catalogPosterRe.firstMatch(block)?.group(1),
        playingDates: progMatch.group(1)!.split('|').map(DateTime.parse).toList(),
      ),
    );
  }
  return result;
}

/// One showtime, as listed under a film's per-cinema schedule page.
class ParsedCineplexxSession {
  const ParsedCineplexxSession({
    required this.localId,
    required this.eventId,
    required this.performanceId,
    required this.day,
    required this.time,
  });

  /// The real Webtic `LocalId` for this showtime's cinema - confirmed live
  /// to sometimes differ from the site's own `siteCinemaId` used to build
  /// this very page's URL (e.g. Cineplexx Bolzano is site id "2360" but
  /// Webtic `LocalId` 5098) - always read from here, never assumed to
  /// match `Cinema.slug`.
  final int localId;
  final String eventId;
  final String performanceId;
  final DateTime day;

  /// "HH:MM", parsed straight off the page.
  final String time;
}

final _dayBlockSplitter = RegExp('li class="hours"');
final _dayNameRe = RegExp(r'<div class="dayName">\s*\S+\s+(\d{2})/(\d{2})');
final _acquistaRe = RegExp(
  r'href="/acquista/[a-z0-9-]+/(\d+)/(\d+)/(\d+)/"[^>]*>\s*(\d{2}):(\d{2})',
);

/// The page only ever prints day/month (e.g. "09/07"), never a year -
/// inferred against [now] the same way as Giometti's programmazione page
/// (see `webtic_programming_page_parser.dart`), so a listing near a year
/// boundary still resolves to the right calendar year.
DateTime _inferYear(int day, int month, DateTime now) {
  var candidate = DateTime(now.year, month, day);
  if (candidate.isBefore(now.subtract(const Duration(days: 60)))) {
    candidate = DateTime(now.year + 1, month, day);
  }
  return candidate;
}

/// Parses one film's per-cinema schedule page
/// (`/scheda/{filmSlug}/{filmId}/{siteCinemaId}/`) into every showtime it
/// has, across every day the page shows (confirmed live: a full week,
/// unlike Giometti's single-day programmazione page).
List<ParsedCineplexxSession> parseWebticFilmSchedulePage(
  String html, {
  required DateTime now,
}) {
  final blocks = html.split(_dayBlockSplitter);
  final result = <ParsedCineplexxSession>[];
  for (final block in blocks.skip(1)) {
    final dayMatch = _dayNameRe.firstMatch(block);
    if (dayMatch == null) continue;
    final day = _inferYear(
      int.parse(dayMatch.group(1)!),
      int.parse(dayMatch.group(2)!),
      now,
    );

    for (final m in _acquistaRe.allMatches(block)) {
      result.add(
        ParsedCineplexxSession(
          localId: int.parse(m.group(1)!),
          eventId: m.group(2)!,
          performanceId: m.group(3)!,
          day: day,
          time: '${m.group(4)}:${m.group(5)}',
        ),
      );
    }
  }
  return result;
}
