import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chains/tmdb/tmdb_film_info_parser.dart';
import '../../core/date/clock.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/network/tmdb_api_client.dart';
import '../../core/storage/film_info_store.dart';

/// Thrown for every "nothing to show" outcome - missing API key, no TMDb
/// match, or a failed request. The UI (film_info_sheet.dart) shows the same
/// single "not available" message for all three, per the design spec.
class FilmInfoUnavailableException implements Exception {}

/// Looks up a film's plot/trailer, in this order: the persistent cache
/// (film_info_store.dart, keyed by the *cleaned* title plus the current
/// language, shared across every cinema/chain that shows this same film)
/// first, then TMDb only if it wasn't already there. Never called just by
/// building this provider - only by a widget actually watching/reading it,
/// which only happens once the user taps the info button (see
/// film_info_sheet.dart).
///
/// `autoDispose`, with no TTL: unlike the chain-API providers above, this is
/// keyed on raw film title, so without it the key space would grow with
/// every distinct film ever tapped for the life of the app. There's no
/// keep-alive to lose any freshness over - the persistent store above
/// already dedupes the real network fetches - so this simply disposes as
/// soon as film_info_sheet.dart's `ref.watch` goes away (the sheet closes),
/// and rebuilds from the persistent cache on the next tap. It still re-runs
/// on language change while the sheet is open, same as before: that comes
/// from `ref.watch(effectiveLocaleProvider)` below, not from being kept
/// alive.
final filmInfoProvider = FutureProvider.autoDispose.family<FilmInfo, String>((
  ref,
  rawTitle,
) async {
  // Locale (and therefore language/cacheKey) and the TMDb client are both
  // read before any `await` so this provider re-runs whenever the app's
  // language changes, on every code path - not just on a cache miss.
  final locale = ref.watch(effectiveLocaleProvider);
  final language = locale.languageCode == 'it' ? 'it-IT' : 'en-US';
  final title = cleanTitleForSearch(rawTitle);
  final cacheKey = '$title|$language';
  final store = ref.watch(filmInfoStoreProvider);
  final client = ref.watch(tmdbApiClientProvider);

  final cached = await store.read(cacheKey);
  if (cached != null) return cached;

  if (tmdbReadAccessToken.isEmpty) throw FilmInfoUnavailableException();

  final searchBody = await client.searchMovie(title, language);
  final searchResult = parseTmdbSearchResult(searchBody);
  if (searchResult == null) throw FilmInfoUnavailableException();

  // The trailer is optional even on a successful match (see the design
  // spec) - a video-fetch failure or "no YouTube trailer" still leaves the
  // overview worth showing, so this is deliberately not inside the same
  // try/catch scope as the search call above.
  String? trailerUrl;
  try {
    final videosBody = await client.getVideos(searchResult.id, language);
    final key = parseTmdbTrailerKey(videosBody);
    if (key != null) trailerUrl = 'https://www.youtube.com/watch?v=$key';
  } catch (_) {
    trailerUrl = null;
  }

  final info = FilmInfo(
    overview: searchResult.overview,
    trailerUrl: trailerUrl,
    fetchedAt: ref.read(clockProvider).now(),
  );
  await store.write(cacheKey, info);
  return info;
});
