enum DayLabelKind { today, tomorrow, other }

/// Resolves whether [showingDate] is today, tomorrow, or another day,
/// **always** computed from [now] rather than trusted from any cached or
/// server-provided value.
///
/// This is the actual fix for the official app's stale-date bug: that app
/// reportedly still shows yesterday as "today" after being reopened the next
/// day, which happens when a resolved day label (or the server's own
/// `datePrefix` field, which is computed at request time) is cached and never
/// recomputed against the real wall-clock date. Here, nothing is ever cached:
/// every call recomputes from scratch, so a stale cache can produce at worst
/// stale *sessions*, never a stale *label*.
DayLabelKind resolveDayLabel(DateTime showingDate, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(showingDate.year, showingDate.month, showingDate.day);
  final diff = target.difference(today).inDays;
  if (diff == 0) return DayLabelKind.today;
  if (diff == 1) return DayLabelKind.tomorrow;
  return DayLabelKind.other;
}

/// The calendar-day string (`yyyy-MM-dd`) for [now], used as a cache-key /
/// rollover marker so callers can detect "the real day changed" without
/// pulling in `intl` just for this.
String todayKey(DateTime now) {
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
