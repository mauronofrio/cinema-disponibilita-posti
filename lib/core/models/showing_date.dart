/// A day for which the cinema may have showings.
///
/// Deliberately does NOT keep the server's `datePrefix` ("Oggi"/"Domani")
/// field: that label is computed by the backend at request time, and
/// trusting/caching it is the root cause of the official app's stale-date
/// bug. Callers must derive the "today/tomorrow" label themselves via
/// `resolveDayLabel` using the device clock, every time they render it.
class ShowingDate {
  const ShowingDate({required this.date, required this.hasShowings});

  factory ShowingDate.fromJson(Map<String, dynamic> json) {
    return ShowingDate(
      date: DateTime.parse(json['showingDate'] as String),
      hasShowings: json['hasShowings'] as bool,
    );
  }

  final DateTime date;
  final bool hasShowings;

  /// Round-trip format of the on-device programme cache (see
  /// ScheduleCacheStore) - not any chain's API shape.
  Map<String, dynamic> toCacheJson() => {
    'date': date.toIso8601String(),
    'hasShowings': hasShowings,
  };

  factory ShowingDate.fromCacheJson(Map<String, dynamic> json) => ShowingDate(
    date: DateTime.parse(json['date'] as String),
    hasShowings: json['hasShowings'] as bool,
  );
}
