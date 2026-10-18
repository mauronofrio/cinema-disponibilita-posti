/// Hour of the day (device-local) after which a cinema's programme for that
/// day is considered final: small cinemas publish or fix the same day's
/// shows in the morning, so a copy fetched before this hour is re-fetched
/// once it has passed - but only when someone actually opens that day.
const scheduleSettledHour = 11;

DateTime _settledAt(DateTime day) =>
    DateTime(day.year, day.month, day.day, scheduleSettledHour);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Whether a saved programme for [day], downloaded at [fetchedAt], can be
/// shown at [now] without asking the cinema again:
/// - downloaded at or after 11:00 of [day] -> final, kept for good;
/// - downloaded earlier -> kept until 11:00 of [day], then stale.
/// So tomorrow's programme seen today is not downloaded again until
/// tomorrow at 11. A [fetchedAt] in the future (clock moved backwards)
/// can't be trusted and counts as stale.
bool isProgrammeFresh({
  required DateTime day,
  required DateTime fetchedAt,
  required DateTime now,
}) {
  if (fetchedAt.isAfter(now)) return false;
  final settled = _settledAt(day);
  return !fetchedAt.isBefore(settled) || now.isBefore(settled);
}

/// Same rule for the list of days a cinema has shows on, which is always
/// about "today": it must also have been downloaded today, or yesterday's
/// list would still offer yesterday as a day.
bool isShowingDatesFresh({required DateTime fetchedAt, required DateTime now}) {
  return _sameDay(fetchedAt, now) &&
      isProgrammeFresh(day: now, fetchedAt: fetchedAt, now: now);
}
