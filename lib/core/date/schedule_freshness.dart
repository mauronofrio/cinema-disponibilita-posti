/// How long a saved programme is shown without asking the cinema again.
/// Short on purpose: cinemas often publish shows and pull them again
/// minutes later, so a copy kept for the whole day could keep showing
/// films that no longer exist.
const scheduleMaxAge = Duration(minutes: 30);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Whether a saved programme downloaded at [fetchedAt] can be shown at
/// [now] without asking the cinema again: only if it is less than
/// [scheduleMaxAge] old. A [fetchedAt] in the future (clock moved
/// backwards) can't be trusted and counts as stale.
bool isProgrammeFresh({required DateTime fetchedAt, required DateTime now}) {
  if (fetchedAt.isAfter(now)) return false;
  return now.difference(fetchedAt) < scheduleMaxAge;
}

/// Same rule for the list of days a cinema has shows on, which is always
/// about "today": it must also have been downloaded today, or yesterday's
/// list would still offer yesterday as a day.
bool isShowingDatesFresh({required DateTime fetchedAt, required DateTime now}) {
  return _sameDay(fetchedAt, now) &&
      isProgrammeFresh(fetchedAt: fetchedAt, now: now);
}
