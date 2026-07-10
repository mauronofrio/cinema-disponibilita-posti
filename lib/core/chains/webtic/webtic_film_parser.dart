import 'dart:convert';

import '../parsing_utils.dart';

/// One showtime for one film, on one specific day - as returned by
/// `getFullSchedule`. Carries [screenId] (needed for the seat map's
/// `getMapSeats` call) since it's only ever exposed here, not anywhere the
/// seat map screen could re-derive it from later.
class ParsedWebticSession {
  const ParsedWebticSession({
    required this.performanceId,
    required this.startTime,
    required this.endTime,
    required this.screenName,
    required this.screenId,
  });

  final String performanceId;
  final DateTime startTime;
  final DateTime endTime;
  final String screenName;
  final int screenId;
}

/// One film's full catalog entry - every session it has, across every day
/// `getFullSchedule` returned, grouped by calendar day.
class ParsedWebticFilm {
  const ParsedWebticFilm({
    required this.eventId,
    required this.title,
    required this.posterPath,
    required this.runningTimeMinutes,
    required this.sessionsByDay,
  });

  final String eventId;
  final String title;

  /// Relative to `https://secure.webtic.it/cvu/modules/` (confirmed live -
  /// this poster handler lives on the shared Webtic backend, not the
  /// chain's own front-end site the rest of the catalog comes from). Null
  /// when the film has no poster at all.
  final String? posterPath;
  final int? runningTimeMinutes;

  /// Keyed by the calendar day (midnight, no time-of-day component) each
  /// group of sessions plays on.
  final Map<DateTime, List<ParsedWebticSession>> sessionsByDay;
}

DateTime _dayKey(DateTime date) => DateTime(date.year, date.month, date.day);

/// Parses a `getFullSchedule` response body into every film it lists, each
/// with every one of its sessions already grouped by day - the one request
/// this whole chain's showtimes/seat-map plumbing is built around (see
/// `WebticChainApi`), unlike 18tickets or UCI which need a call per day.
List<ParsedWebticFilm> parseWebticFullSchedule(String responseBody) {
  final decoded = json.decode(responseBody) as Map<String, dynamic>;
  final scheduling = decoded['DS'] as Map<String, dynamic>?;
  final events =
      (scheduling?['Scheduling'] as Map<String, dynamic>?)?['Events']
          as List<dynamic>? ??
      const [];

  return events.map((eventJson) {
    final event = eventJson as Map<String, dynamic>;
    final days = (event['Days'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();

    final sessionsByDay = <DateTime, List<ParsedWebticSession>>{};
    for (final day in days) {
      final dayDate = _dayKey(DateTime.parse(day['Day'] as String));
      final performances = (day['Performances'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      sessionsByDay[dayDate] = performances
          .map(
            (p) => ParsedWebticSession(
              performanceId: p['PerformanceId'].toString(),
              startTime: DateTime.parse(p['StartTime'] as String),
              endTime: DateTime.parse(p['EndTime'] as String),
              screenName: (p['Screen'] as String?) ?? '',
              screenId: (p['ScreenId'] as num).toInt(),
            ),
          )
          .toList();
    }

    return ParsedWebticFilm(
      eventId: event['EventId'].toString(),
      title: (event['Title'] as String?) ?? '',
      posterPath: event['Picture'] as String?,
      runningTimeMinutes: parseDurationMinutes(event['Duration'] as String?),
      sessionsByDay: sessionsByDay,
    );
  }).toList();
}

/// Every calendar day any film has at least one session on - the whole
/// day-picker's contents come from this same `getFullSchedule` response,
/// same reasoning as [parseWebticFullSchedule] (one call, no per-day cost).
List<DateTime> parseWebticShowingDays(String responseBody) {
  final days = <DateTime>{};
  for (final film in parseWebticFullSchedule(responseBody)) {
    days.addAll(film.sessionsByDay.keys);
  }
  return days.toList()..sort();
}
