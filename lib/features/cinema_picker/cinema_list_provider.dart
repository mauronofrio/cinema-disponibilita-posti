import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/catalog/cinema_catalog_repository.dart';
import '../../core/models/cinema.dart';
import '../../core/storage/favorite_cinema_store.dart';

/// Every cinema this app version can show: cached-or-bundled immediately,
/// then - at most once a day - refreshed from GitHub in the background
/// (see CinemaCatalogRepository). When a refresh brings a new valid list
/// the provider rebuilds itself, so the picker updates without a restart.
final cinemaListProvider = FutureProvider<List<Cinema>>((ref) async {
  final repo = ref.watch(cinemaCatalogRepositoryProvider);
  final version = await ref.watch(appVersionProvider.future);
  final cinemas = await repo.load(appVersion: version);
  repo.refreshIfStale(appVersion: version).then((changed) {
    if (changed) ref.invalidateSelf();
  }).ignore();
  return cinemas;
});

/// The installed app's version ("1.0.8"), used to hide catalog entries that
/// need a newer one. Overridden in tests.
final appVersionProvider = FutureProvider<String>((ref) async {
  return (await PackageInfo.fromPlatform()).version;
});

final favoriteCinemaStoreProvider = Provider<FavoriteCinemaStore>(
  (ref) => FavoriteCinemaStore(),
);

/// The user's saved favorite cinema ids, in the order they were added.
final favoriteCinemaIdsProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(favoriteCinemaStoreProvider).readFavorites();
});

/// Which of the favorites is currently active (the one the home screen
/// shows), or null if there are no favorites yet.
final activeCinemaIdProvider = FutureProvider<String?>((ref) {
  return ref.watch(favoriteCinemaStoreProvider).readActive();
});

/// The user's favorite cinemas resolved to full [Cinema] records, in the
/// order they were added. A stored key with no matching cinema (e.g. an old
/// bare-cinemaId entry from before favorites were namespaced by chain) is
/// silently dropped, same as any other "cinema no longer in the list" case -
/// no separate migration step.
final favoriteCinemasProvider = FutureProvider<List<Cinema>>((ref) async {
  final ids = await ref.watch(favoriteCinemaIdsProvider.future);
  final cinemas = await ref.watch(cinemaListProvider.future);
  final byKey = {for (final c in cinemas) FavoriteCinemaStore.keyFor(c): c};
  return [
    for (final id in ids)
      if (byKey[id] != null) byKey[id]!,
  ];
});

/// The currently active favorite cinema, resolved to its full [Cinema]
/// record - what the home screen actually shows showtimes for.
final activeCinemaProvider = FutureProvider<Cinema?>((ref) async {
  final id = await ref.watch(activeCinemaIdProvider.future);
  if (id == null) return null;
  final cinemas = await ref.watch(cinemaListProvider.future);
  for (final cinema in cinemas) {
    if (FavoriteCinemaStore.keyFor(cinema) == id) return cinema;
  }
  return null;
});
