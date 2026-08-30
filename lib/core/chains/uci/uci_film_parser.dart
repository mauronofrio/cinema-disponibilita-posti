import '../../models/film.dart';
import '../parsing_utils.dart';

/// One film's showings on one specific day, before merging across every day
/// the cinema publishes - see [UciChainApi.getFilmsForCinema] for why this
/// merge is needed at all (UCI has no single "every day" endpoint the way
/// The Space does).
class ParsedUciDay {
  const ParsedUciDay({
    required this.filmId,
    required this.title,
    required this.posterImageSrc,
    required this.runningTime,
    required this.date,
    required this.sessions,
  });

  final String filmId;
  final String title;
  final String? posterImageSrc;
  final int? runningTime;
  final DateTime date;
  final List<Session> sessions;
}

List<SessionAttribute> _attributesFor(
  String formatKey,
  Map<String, dynamic> variant,
) {
  final attributes = <SessionAttribute>[];
  if (formatKey.isNotEmpty && formatKey != '2D') {
    attributes.add(
      SessionAttribute(name: formatKey, attributeType: 'screen', color: null),
    );
  }
  // Every variant carries its own language (name "ITA"/"ENG", not just non-
  // Italian ones - confirmed live, e.g. UCI Bicocca Milano's "Oceania" has
  // both ITA and EN performances the same day). Tagged unconditionally, the
  // same way The Space always tags its own Language attribute, so a mixed
  // film's Italian and original-language showings both get a group label
  // instead of only the non-Italian one - see groupSessionsByLanguage.
  final language = variant['language'] as Map<String, dynamic>?;
  final languageName = language?['name'] as String?;
  if (languageName != null) {
    attributes.add(
      SessionAttribute(
        name: languageName,
        attributeType: 'Language',
        color: null,
      ),
    );
  }
  return attributes;
}

/// Parses one day's `GET /theatres/{slug}/programming/{date}` response (see
/// PROJECT_NOTES.md) into one entry per film showing that day.
///
/// `screens` in the raw response is a list of maps, each with exactly one
/// key - the format ("2D"/"3D"/"IMAX"/...) - mapping to the list of
/// language/subtitle "variants" for that format, each carrying its own
/// `performances`. This flattens all of that into a single, already-sorted
/// [Session] list per film, with format/language folded into
/// [Session.attributes] so the existing film-card chip UI picks them up for
/// free.
List<ParsedUciDay> parseUciProgrammingDay(
  List<dynamic> filmsJson,
  DateTime date,
) {
  final result = <ParsedUciDay>[];
  for (final filmJson in filmsJson.cast<Map<String, dynamic>>()) {
    final sessions = <Session>[];
    String? runningTimeDuration;
    final screens = filmJson['screens'] as List<dynamic>? ?? const [];
    for (final screenEntry in screens.cast<Map<String, dynamic>>()) {
      for (final formatKey in screenEntry.keys) {
        final variants = screenEntry[formatKey] as List<dynamic>? ?? const [];
        for (final variant in variants.cast<Map<String, dynamic>>()) {
          runningTimeDuration ??= variant['duration'] as String?;
          final attributes = _attributesFor(formatKey, variant);
          final performances =
              variant['performances'] as List<dynamic>? ?? const [];
          for (final performance in performances.cast<Map<String, dynamic>>()) {
            sessions.add(
              Session(
                sessionId: performance['external_id'].toString(),
                startTime: DateTime.parse(performance['starts_at'] as String),
                endTime: DateTime.parse(performance['ends_at'] as String),
                screenName: (performance['room'] as String?) ?? '',
                // Always false off The Space - see [Session.isSoldOut]: no other
                // chain publishes it, and deriving it would cost one seat-map
                // request per showtime.
                isSoldOut: false,
                formattedPrice: null,
                isPriceVisible: false,
                attributes: attributes,
                // Same idea as The Space's own bookingPath: a relative
                // "/movies/{slug}/acquista/{LocalId}/{event_external_id}/
                // {external_id}" path straight from the API, made absolute
                // here so BuyTicketsButton can treat both chains the same.
                bookingPath: performance['cart_link'] == null
                    ? null
                    : 'https://ucicinemas.it${performance['cart_link']}',
                webticScreenId: (performance['room_id'] as num?)?.toInt(),
              ),
            );
          }
        }
      }
    }
    if (sessions.isEmpty) continue;
    sessions.sort((a, b) => a.startTime.compareTo(b.startTime));
    result.add(
      ParsedUciDay(
        filmId: filmJson['id'].toString(),
        title: (filmJson['title'] as String?) ?? '',
        posterImageSrc:
            (filmJson['poster'] as String?) ?? filmJson['top_image'] as String?,
        runningTime: parseDurationMinutes(runningTimeDuration),
        date: date,
        sessions: sessions,
      ),
    );
  }
  return result;
}
