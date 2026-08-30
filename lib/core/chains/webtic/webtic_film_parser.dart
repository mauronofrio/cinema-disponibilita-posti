import 'dart:convert';

import '../parsing_utils.dart';

/// One showtime for one film, on one specific day - as returned by
/// `getFullSchedule`.
///
/// Used to also carry `screenId` (`ScreenId` from the raw response) on the
/// claim it was "needed for the seat map's getMapSeats call" - that stopped
/// being true once `WebticChainApi.getSeatMap` started deriving the room id
/// from `getOccupancy`'s own `idsala` field instead (see that class's doc
/// comment, "the idsala shortcut"), but the field itself, and its hard
/// `as num` cast on every single performance in the catalog, stuck around
/// unused. Removed rather than given a safe fallback like the audit's other
/// stale-cast fixes: nothing reads it (confirmed with a grep), so there's no
/// behaviour to preserve, only a cast to stop letting one performance
/// missing `ScreenId` kill an entire cinema's catalog for a field nothing
/// uses.
class ParsedWebticSession {
  const ParsedWebticSession({
    required this.performanceId,
    required this.startTime,
    required this.endTime,
    required this.screenName,
  });

  final String performanceId;
  final DateTime startTime;
  final DateTime endTime;
  final String screenName;
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
