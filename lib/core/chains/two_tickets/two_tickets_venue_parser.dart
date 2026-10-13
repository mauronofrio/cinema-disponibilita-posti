import '../../util/html_entities.dart';

/// One cinema title listed on a 2Tickets venue page - metadata only, the
/// showtimes live on the film's own checkout page (see
/// two_tickets_checkout_parser.dart).
class TwoTicketsVenueFilm {
  const TwoTicketsVenueFilm({
    required this.filmId,
    required this.title,
    required this.posterUrl,
    required this.runningTime,
  });

  final String filmId;
  final String title;
  final String? posterUrl;
  final int? runningTime;
}

class TwoTicketsVenuePage {
  const TwoTicketsVenuePage({
    required this.name,
    required this.address,
    required this.films,
  });

  final String name;
  final String address;
  final List<TwoTicketsVenueFilm> films;
}

final _header = RegExp(
  r'<div class="cinema-header">\s*<h1>(.*?)</h1>\s*<p>(.*?)</p>',
  dotAll: true,
);
final _card = RegExp(
  r'<div class="titolo-card"(.*?)<div class="btn-fasticket-container">',
  dotAll: true,
);
final _checkoutLink = RegExp(r'Acquisto/Checkout/(\d+)/\d+\?settore=(\w)');
final _tag = RegExp(r'bi-tag-fill"></i>\s*([^<]+)<');
final _title = RegExp(r'<h3 class="titolo-title">(.*?)</h3>', dotAll: true);
final _poster = RegExp(r'<img src="([^"]+)"');
final _minutes = RegExp(r'(\d+)\s*min\b');
final _tags = RegExp(r'<[^>]*>');
final _spaces = RegExp(r'\s+');

/// 2Tickets titles come out of the venue's own database with SQL-style
/// doubled apostrophes ("L''ESTRANEA") and, now and then, trailing spaces.
String cleanTwoTicketsTitle(String raw) => decodeHtmlEntities(raw)
    .replaceAll("''", "'")
    .replaceAll(_spaces, ' ')
    .trim();

/// Parses `/biglietto/esercizio/titoli/{idLocale}`.
///
/// The same venue often sells theatre too (Cine Teatro Norba lists 8 plays
/// alongside 6 films) - a title is kept only when its link carries
/// `settore=C` **and** its tag says CINEMA. Filtering by venue name would
/// be wrong: many real cinemas are called "Cinema Teatro ...".
TwoTicketsVenuePage parseTwoTicketsVenuePage(String html) {
  final header = _header.firstMatch(html);
  final name = header == null ? '' : cleanTwoTicketsTitle(header.group(1)!);
  final address = header == null
      ? ''
      : decodeHtmlEntities(header.group(2)!.replaceAll(_tags, ' '))
          .replaceAll(_spaces, ' ')
          .trim();

  final films = <TwoTicketsVenueFilm>[];
  for (final card in _card.allMatches(html)) {
    final body = card.group(1)!;
    final link = _checkoutLink.firstMatch(body);
    if (link == null || link.group(2) != 'C') continue;
    final tag = _tag.firstMatch(body)?.group(1)?.trim().toUpperCase() ?? '';
    if (!tag.contains('CINEMA')) continue;
    final title = _title.firstMatch(body);
    if (title == null) continue;
    final poster = _poster.firstMatch(body)?.group(1);
    films.add(
      TwoTicketsVenueFilm(
        filmId: link.group(1)!,
        title: cleanTwoTicketsTitle(title.group(1)!),
        posterUrl: poster == null || poster.contains('locandina_null')
            ? null
            : poster,
        runningTime: int.tryParse(_minutes.firstMatch(body)?.group(1) ?? ''),
      ),
    );
  }
  return TwoTicketsVenuePage(name: name, address: address, films: films);
}
