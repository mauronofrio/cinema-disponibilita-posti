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
  // Calendar days compared in UTC, not as local midnights: on a DST switch
  // day two local midnights are 23h or 25h apart, and `inDays` truncates
  // 23h to 0 - so on the spring-forward Sunday tomorrow read as a second
  // "today". UTC has no DST, so every day is exactly 24h.
  final today = DateTime.utc(now.year, now.month, now.day);
  final target = DateTime.utc(
    showingDate.year,
    showingDate.month,
    showingDate.day,
  );
  final diff = target.difference(today).inDays;
  if (diff == 0) return DayLabelKind.today;
  if (diff == 1) return DayLabelKind.tomorrow;
  return DayLabelKind.other;
}

/// Which day should show as selected, given what was previously chosen (by
/// the user, or by an earlier auto-default) and the days actually available
/// right now. Falls back to the first available day whenever [selected] is
/// `null` **or** no longer present in [availableDates] - the latter is what
/// makes a day rollover self-correct: once the calendar day advances, a
/// previously-picked "today" ages out of the fresh list and this recomputes
/// a real today instead of staying pinned to a date that's now in the past.
DateTime pickSelectedDay(DateTime? selected, List<DateTime> availableDates) {
  if (selected != null &&
      availableDates.any(
        (d) =>
            d.year == selected.year &&
            d.month == selected.month &&
            d.day == selected.day,
      )) {
    return selected;
  }
  return availableDates.first;
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
