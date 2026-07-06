import 'package:shared_preferences/shared_preferences.dart';

/// Persists exactly one value: the id of the user's favorite cinema.
/// No account/login/booking data is ever stored — this app is a read-only
/// viewer, so this is the entirety of its local persistence.
class FavoriteCinemaStore {
  static const _key = 'favorite_cinema_id';

  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> write(String cinemaId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, cinemaId);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
