// Small parsing helpers shared across more than one chain's parser.

/// "01:50" -> 110. Absent or malformed just means "unknown", not an error -
/// callers already treat a null running time as fine to omit.
int? parseDurationMinutes(String? duration) {
  if (duration == null) return null;
  final parts = duration.split(':');
  if (parts.length != 2) return null;
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);
  if (hours == null || minutes == null) return null;
  return hours * 60 + minutes;
}

/// A row's real label, found by majority vote across every seat id in it,
/// rather than trusting whichever seat happens to be listed first.
///
/// Both UCI and Webtic identify a seat with an id shaped
/// `"{rowPrefix}/{number}"` (UCI's own `SeatId`, e.g. `"G/3"` or the
/// accessibility prefix `"HX/1"`; Webtic's own `idposto`, same shape
/// natively) - and on both platforms a row's one or two dedicated
/// accessibility seats can sort ahead of that row's own regular seats in
/// the raw array. Confirmed live at UCI Bicocca Milano: a 14-seat "G" row's
/// two wheelchair spots (`HX/1`, `HX/2`) come first, so naively reading the
/// row label off `seatsInRow.first` calls the whole row "HX" and makes the
/// real "G" row (and its accessibility seats) impossible to find. The
/// prefix shared by the *most* seats in the row is never one of those - so
/// it's the real row label.
String rowLabelByMajorityPrefix(Iterable<String> seatIds) {
  final counts = <String, int>{};
  for (final seatId in seatIds) {
    final prefix = seatId.split('/').first;
    counts[prefix] = (counts[prefix] ?? 0) + 1;
  }
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}
