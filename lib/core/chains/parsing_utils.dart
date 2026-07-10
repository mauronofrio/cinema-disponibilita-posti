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
