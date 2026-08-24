import '../network/dio_provider.dart' show theSpaceBaseUrl;

class SessionAttribute {
  const SessionAttribute({
    required this.name,
    required this.attributeType,
    required this.color,
  });

  factory SessionAttribute.fromJson(Map<String, dynamic> json) {
    return SessionAttribute(
      name: (json['name'] as String?) ?? '',
      attributeType: (json['attributeType'] as String?) ?? '',
      color: json['color'] as String?,
    );
  }

  final String name;
  final String attributeType;
  final String? color;
}

class Session {
  const Session({
    required this.sessionId,
    required this.startTime,
    required this.endTime,
    required this.screenName,
    required this.isSoldOut,
    required this.formattedPrice,
    required this.isPriceVisible,
    required this.attributes,
    required this.bookingPath,
    this.webticScreenId,
    this.eighteenTicketsFilmId,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      sessionId: json['sessionId'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      screenName: (json['screenName'] as String?) ?? '',
      isSoldOut: (json['isSoldOut'] as bool?) ?? false,
      formattedPrice: json['formattedPrice'] as String?,
      isPriceVisible: (json['isPriceVisible'] as bool?) ?? false,
      attributes: (json['attributes'] as List<dynamic>? ?? const [])
          .map((a) => SessionAttribute.fromJson(a as Map<String, dynamic>))
          .where((a) => a.name.isNotEmpty)
          .toList(),
      // Full URL to the official site's own booking flow for this exact
      // session - this app never implements booking itself, it just hands
      // off to the real site. The API only gives a relative path (e.g.
      // "/prenotare-il-biglietto/summary/1024/HO.../52619"); stored here as
      // an absolute URL so callers (BuyTicketsButton) don't need to know
      // which chain's own base domain it belongs to.
      bookingPath: (json['bookingUrl'] as String?) == null
          ? null
          : '$theSpaceBaseUrl${json['bookingUrl']}',
    );
  }

  final String sessionId;
  final DateTime startTime;
  final DateTime endTime;
  final String screenName;
  final bool isSoldOut;
  final String? formattedPrice;
  final bool isPriceVisible;
  final List<SessionAttribute> attributes;
  final String? bookingPath;

  /// UCI Cinemas only: WebTic's `ScreenId` for this session's room (the
  /// myuci programming response calls it `room_id`) - needed alongside the
  /// cinema's `webticLocalId` to fetch the seat layout/occupancy. Null for
  /// The Space, which doesn't need it (its own `sessionId` is enough).
  final int? webticScreenId;

  /// 18tickets-platform cinemas only (RedCarpet, Multicinema Galleria, ...):
  /// the film's own id, needed alongside [sessionId] to fetch that one
  /// showtime's own page (`/film/{filmId}/{sessionId}`) - the only place
  /// this platform exposes which room a showtime plays in, resolved lazily
  /// from there rather than known upfront (see
  /// EighteenTicketsChainApi.getSeatMap).
  final String? eighteenTicketsFilmId;

  /// A session is the same session iff same [sessionId] - it's already a
  /// unique identifier for one specific showtime, so this is entity
  /// identity, not a field-by-field value comparison. Used as (part of) a
  /// Riverpod provider key for the seat map, so this needs to hold across
  /// separately-parsed instances of "the same" session too.
  @override
  bool operator ==(Object other) =>
      other is Session && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}

/// Groups [sessions] by their `Language` session attribute (The Space uses
/// this to flag "ITALIANO" vs "LINGUA ORIGINALE" showings of the same film,
/// e.g. a sing-along matinee alongside the regular dubbed evening shows).
/// `null` is the group key for sessions with no such attribute at all -
/// every other chain, and the common case where a film only has one
/// language - so those collapse into a single group instead of spuriously
/// splitting. Both the sessions within a group and which group's key was
/// first seen keep the original list's order.
Map<String?, List<Session>> groupSessionsByLanguage(List<Session> sessions) {
  final groups = <String?, List<Session>>{};
  for (final session in sessions) {
    String? language;
    for (final attribute in session.attributes) {
      if (attribute.attributeType == 'Language') {
        language = attribute.name;
        break;
      }
    }
    (groups[language] ??= []).add(session);
  }
  return groups;
}

/// Language values common enough that they're not worth labeling on their
/// own - confirmed live for the two chains that currently tag Language: The
/// Space uses "ITALIANO", UCI uses "ITA".
const _defaultLanguages = {'ITALIANO', 'ITA'};

/// Whether [language] is worth showing a caption for even when it's the
/// *only* language a film has that day. A lone default-language group (or
/// no Language attribute at all) stays silent, same as before this
/// existed; but a lone non-default one - most notably an original-language
/// showing with no dubbed alternative that day, e.g. UCI Seven Gioia del
/// Colle's "Katy Perry: The Lifetimes Tour" (ENG only, 5 Sept 2026, no
/// ITA showing at all) - would otherwise render with no indication
/// whatsoever that it isn't a normal Italian showing.
bool isNotableLanguage(String? language) =>
    language != null && !_defaultLanguages.contains(language);

class ShowingGroup {
  const ShowingGroup({required this.date, required this.sessions});

  factory ShowingGroup.fromJson(Map<String, dynamic> json) {
    return ShowingGroup(
      date: DateTime.parse(json['date'] as String),
      sessions: (json['sessions'] as List<dynamic>? ?? const [])
          .map((s) => Session.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  final DateTime date;
  final List<Session> sessions;
}

class Film {
  const Film({
    required this.filmId,
    required this.title,
    required this.posterImageSrc,
    required this.runningTime,
    required this.showingGroups,
  });

  factory Film.fromJson(Map<String, dynamic> json) {
    return Film(
      filmId: json['filmId'] as String,
      title: (json['filmTitle'] as String?) ?? '',
      posterImageSrc: json['posterImageSrc'] as String?,
      runningTime: (json['runningTime'] as num?)?.toInt(),
      showingGroups: (json['showingGroups'] as List<dynamic>? ?? const [])
          .map((g) => ShowingGroup.fromJson(g as Map<String, dynamic>))
          .toList(),
    );
  }

  final String filmId;
  final String title;
  final String? posterImageSrc;
  final int? runningTime;
  final List<ShowingGroup> showingGroups;

  /// Sessions for this film on the given calendar day, or an empty list.
  List<Session> sessionsOn(DateTime day) {
    for (final group in showingGroups) {
      if (group.date.year == day.year &&
          group.date.month == day.month &&
          group.date.day == day.day) {
        return group.sessions;
      }
    }
    return const [];
  }
}
