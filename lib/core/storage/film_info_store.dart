import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One film's TMDb data, cached exactly as shown in the UI - no re-fetch
/// logic lives here, this is pure storage.
class FilmInfo {
  const FilmInfo({
    required this.overview,
    required this.trailerUrl,
    required this.fetchedAt,
  });

  final String overview;
  final String? trailerUrl;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => {
    'overview': overview,
    'trailerUrl': trailerUrl,
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  factory FilmInfo.fromJson(Map<String, dynamic> json) => FilmInfo(
    overview: json['overview'] as String,
    trailerUrl: json['trailerUrl'] as String?,
    fetchedAt: DateTime.parse(json['fetchedAt'] as String),
  );
}

/// Persists TMDb film info keyed by film *title* only (never by cinema or
/// chain) - the whole point is that asking once for a film shown at one
/// cinema must never trigger a second TMDb call for the same film shown at
/// another cinema, or reopened later. One shared_preferences entry holding
/// a JSON map, same "small enough that a single key is simpler than one key
/// per entry" reasoning as [FavoriteCinemaStore]'s own two keys - realistic
/// scale here is at most a few hundred films ever, a few KB total.
class FilmInfoStore {
  static const _prefsKey = 'film_info_cache';

  Future<Map<String, dynamic>> _readAll(SharedPreferences prefs) async {
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {};
    return json.decode(raw) as Map<String, dynamic>;
  }

  Future<FilmInfo?> read(String title) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll(prefs);
    final entry = all[title] as Map<String, dynamic>?;
    if (entry == null) return null;
    return FilmInfo.fromJson(entry);
  }

  Future<void> write(String title, FilmInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll(prefs);
    all[title] = info.toJson();
    await prefs.setString(_prefsKey, json.encode(all));
  }

  /// Called once at app startup (see app.dart) - not a TTL on read, just
  /// housekeeping so the cache doesn't grow forever across months of use.
  Future<void> purgeOlderThan(DateTime cutoff) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll(prefs);
    all.removeWhere((_, value) {
      final fetchedAt = DateTime.parse(
        (value as Map<String, dynamic>)['fetchedAt'] as String,
      );
      return fetchedAt.isBefore(cutoff);
    });
    await prefs.setString(_prefsKey, json.encode(all));
  }
}

final filmInfoStoreProvider = Provider<FilmInfoStore>((ref) => FilmInfoStore());
