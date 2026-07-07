import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'language_override';

/// Persists the user's explicit language choice, if any. Absent that,
/// [effectiveLocale] falls back to the device's own locale - Italian if the
/// device country is Italy, English otherwise, since English is this app's
/// default language.
class LanguageStore {
  Future<String?> readOverride() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey);
  }

  Future<void> setOverride(String? languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    if (languageCode == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, languageCode);
    }
  }
}

final languageStoreProvider = Provider<LanguageStore>((ref) => LanguageStore());

/// The user's saved override ('it'/'en'), or null if they've never changed
/// it from the automatic default.
final languageOverrideProvider = FutureProvider<String?>((ref) {
  return ref.watch(languageStoreProvider).readOverride();
});

Locale _systemDefaultLocale() {
  final systemLocale = PlatformDispatcher.instance.locale;
  return systemLocale.countryCode == 'IT'
      ? const Locale('it')
      : const Locale('en');
}

/// The locale actually in effect: the user's override if they've set one,
/// otherwise a one-time guess from the device's own country.
final effectiveLocaleProvider = Provider<Locale>((ref) {
  final override = ref.watch(languageOverrideProvider).value;
  if (override != null) return Locale(override);
  return _systemDefaultLocale();
});
