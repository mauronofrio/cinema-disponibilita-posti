import 'package:shared_preferences/shared_preferences.dart';

import '../models/cinema.dart';

/// Persists the user's favorite cinemas (an ordered list of ids) and which
/// one is currently active. No account/login/booking data is ever stored -
/// this app is a read-only viewer, so this is the entirety of its local
/// persistence.
class FavoriteCinemaStore {
  static const _favoritesKey = 'favorite_cinema_ids';
  static const _activeKey = 'active_cinema_id';

  /// Cinema ids are only unique within their own chain (see the doc comment
  /// on [Cinema.==]), so the persisted key must include the chain too -
  /// otherwise a future id collision across chains could resolve a favorite
  /// to the wrong cinema. `chain.name` is the same string [CinemaChain]
  /// already uses for JSON (see [CinemaChain.fromJson]), reused here instead
  /// of inventing a separate format. Public (and static) so callers that only
  /// have the persisted key (e.g. resolving it back to a [Cinema]) can build
  /// the same key without duplicating the format.
  static String keyFor(Cinema cinema) =>
      '${cinema.chain.name}:${cinema.cinemaId}';

  String _key(Cinema cinema) => keyFor(cinema);

  Future<List<String>> readFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_favoritesKey) ?? const [];
  }

  Future<String?> readActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeKey);
  }

  /// Adds [cinema] to the favorites (no-op if already there) and makes it
  /// the active one - picking a cinema always means "show me this one now".
  Future<void> addAndActivate(Cinema cinema) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(cinema);
    final favorites = prefs.getStringList(_favoritesKey) ?? <String>[];
    if (!favorites.contains(key)) {
      favorites.add(key);
      await prefs.setStringList(_favoritesKey, favorites);
    }
    await prefs.setString(_activeKey, key);
  }

  Future<void> setActive(Cinema cinema) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, _key(cinema));
  }

  /// Removes [cinema] from the favorites list. If it was the active one,
  /// promotes the first remaining favorite to active, or clears active
  /// entirely if none are left.
  Future<void> remove(Cinema cinema) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(cinema);
    final favorites = prefs.getStringList(_favoritesKey) ?? <String>[];
    favorites.remove(key);
    await prefs.setStringList(_favoritesKey, favorites);
    if (prefs.getString(_activeKey) == key) {
      if (favorites.isEmpty) {
        await prefs.remove(_activeKey);
      } else {
        await prefs.setString(_activeKey, favorites.first);
      }
    }
  }
}
