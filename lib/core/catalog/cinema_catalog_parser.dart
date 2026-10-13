import 'dart:convert';

import '../models/cinema.dart';
import '../update/update_checker.dart' show isNewerVersion;

/// Parses a cinema catalog body (bundled asset or downloaded from GitHub)
/// into the cinemas *this app version* can actually show. Malformed entries,
/// entries with values this version doesn't know, and entries whose
/// `minAppVersion` is newer than [appVersion] are dropped - never guessed.
/// Throws [FormatException] only when the body isn't a JSON list at all.
List<Cinema> parseCinemaCatalog(String body, {required String appVersion}) {
  final Object? decoded = jsonDecode(body);
  if (decoded is! List) {
    throw const FormatException('Cinema catalog is not a JSON list');
  }
  final result = <Cinema>[];
  for (final raw in decoded) {
    if (raw is! Map<String, dynamic>) continue;
    final cinema = Cinema.tryFromJson(raw);
    if (cinema == null) continue;
    final min = cinema.minAppVersion;
    if (min != null && isNewerVersion(current: appVersion, latest: min)) {
      continue;
    }
    result.add(cinema);
  }
  return result;
}
