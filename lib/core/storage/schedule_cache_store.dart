import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cinema.dart';
import '../models/film.dart';
import '../models/showing_date.dart';

/// A saved programme plus when it was downloaded; whether it may still be
/// shown is decided by the caller (see schedule_freshness.dart).
class CachedSchedule<T> {
  const CachedSchedule(this.data, this.fetchedAt);

  final T data;
  final DateTime fetchedAt;
}

/// On-device copy of each cinema's programme, so switching between cinemas
/// or reopening the app doesn't ask the cinema's servers again for data we
/// already have - they're third-party APIs, some with tight rate limits.
///
/// One shared_preferences key per cinema and day (not one big blob like
/// FilmInfoStore): a write only touches the day just downloaded. Entries
/// for past days are dropped by [purgeBefore] at startup. Any unreadable
/// entry is a plain cache miss - the programme is downloaded again and the
/// entry overwritten.
class ScheduleCacheStore {
  static const _prefix = 'schedule_v1|';

  static String _cinemaKey(Cinema c) => '${c.chain.name}|${c.cinemaId}';

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _filmsKey(Cinema c, DateTime day) =>
      '${_prefix}films|${_cinemaKey(c)}|${_dayKey(day)}';

  static String _datesKey(Cinema c) => '${_prefix}dates|${_cinemaKey(c)}';

  /// Never throws: storage trouble reads as "nothing saved".
  Future<CachedSchedule<T>?> _read<T>(
    String key,
    T Function(List<dynamic>) decode,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final entry = json.decode(raw) as Map<String, dynamic>;
      return CachedSchedule(
        decode(entry['data'] as List<dynamic>),
        DateTime.parse(entry['fetchedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  /// Never throws: failing to save a programme must not hide the programme
  /// just downloaded - it is simply downloaded again next time.
  Future<void> _write(String key, Object data, DateTime fetchedAt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        json.encode({'fetchedAt': fetchedAt.toIso8601String(), 'data': data}),
      );
    } catch (_) {}
  }

  Future<CachedSchedule<List<Film>>?> readFilms(Cinema cinema, DateTime day) {
    return _read(
      _filmsKey(cinema, day),
      (list) => [
        for (final f in list) Film.fromCacheJson(f as Map<String, dynamic>),
      ],
    );
  }

  /// Stores only [day]'s sessions: chains that answer with every day at
  /// once (The Space, UCI) would otherwise save the whole week once per day.
  Future<void> writeFilms(
    Cinema cinema,
    DateTime day,
    List<Film> films,
    DateTime fetchedAt,
  ) {
    final data = <Map<String, dynamic>>[];
    for (final film in films) {
      final sessions = film.sessionsOn(day);
      if (sessions.isEmpty) continue;
      data.add(
        Film(
          filmId: film.filmId,
          title: film.title,
          posterImageSrc: film.posterImageSrc,
          runningTime: film.runningTime,
          showingGroups: [ShowingGroup(date: day, sessions: sessions)],
        ).toCacheJson(),
      );
    }
    return _write(_filmsKey(cinema, day), data, fetchedAt);
  }

  Future<CachedSchedule<List<ShowingDate>>?> readShowingDates(Cinema cinema) {
    return _read(
      _datesKey(cinema),
      (list) => [
        for (final d in list)
          ShowingDate.fromCacheJson(d as Map<String, dynamic>),
      ],
    );
  }

  Future<void> writeShowingDates(
    Cinema cinema,
    List<ShowingDate> dates,
    DateTime fetchedAt,
  ) => _write(_datesKey(cinema), [
    for (final d in dates) d.toCacheJson(),
  ], fetchedAt);

  /// Pull-to-refresh: forget [cinema]'s saved list of days and, if given,
  /// [day]'s programme, so the next read downloads them again.
  Future<void> forget(Cinema cinema, {DateTime? day}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_datesKey(cinema));
      if (day != null) await prefs.remove(_filmsKey(cinema, day));
    } catch (_) {}
  }

  /// Startup housekeeping: drops programmes of days before [today] and
  /// lists of days not downloaded today - none of them can be shown again.
  Future<void> purgeBefore(DateTime today) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _dayKey(today);
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith(_prefix)) continue;
      final String? kept;
      if (key.startsWith('${_prefix}films|')) {
        kept = key.substring(key.lastIndexOf('|') + 1);
      } else {
        try {
          final raw =
              json.decode(prefs.getString(key)!) as Map<String, dynamic>;
          kept = _dayKey(DateTime.parse(raw['fetchedAt'] as String));
        } catch (_) {
          await prefs.remove(key);
          continue;
        }
      }
      // yyyy-MM-dd strings compare like the dates they spell.
      if (kept.compareTo(todayKey) < 0) await prefs.remove(key);
    }
  }
}

final scheduleCacheStoreProvider = Provider<ScheduleCacheStore>(
  (ref) => ScheduleCacheStore(),
);
