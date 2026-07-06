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
}

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
