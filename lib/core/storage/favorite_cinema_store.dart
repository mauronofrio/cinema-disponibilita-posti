import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's favorite cinemas (an ordered list of ids) and which
/// one is currently active. No account/login/booking data is ever stored -
/// this app is a read-only viewer, so this is the entirety of its local
/// persistence.
class FavoriteCinemaStore {
  static const _favoritesKey = 'favorite_cinema_ids';
  static const _activeKey = 'active_cinema_id';

  Future<List<String>> readFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_favoritesKey) ?? const [];
  }

  Future<String?> readActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeKey);
  }

  /// Adds [cinemaId] to the favorites (no-op if already there) and makes it
  /// the active one - picking a cinema always means "show me this one now".
  Future<void> addAndActivate(String cinemaId) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList(_favoritesKey) ?? <String>[];
    if (!favorites.contains(cinemaId)) {
      favorites.add(cinemaId);
      await prefs.setStringList(_favoritesKey, favorites);
    }
    await prefs.setString(_activeKey, cinemaId);
  }

  Future<void> setActive(String cinemaId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, cinemaId);
  }

  /// Removes [cinemaId] from the favorites list. If it was the active one,
  /// promotes the first remaining favorite to active, or clears active
  /// entirely if none are left.
  Future<void> remove(String cinemaId) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList(_favoritesKey) ?? <String>[];
    favorites.remove(cinemaId);
    await prefs.setStringList(_favoritesKey, favorites);
    if (prefs.getString(_activeKey) == cinemaId) {
      if (favorites.isEmpty) {
        await prefs.remove(_activeKey);
      } else {
        await prefs.setString(_activeKey, favorites.first);
      }
    }
  }
}
