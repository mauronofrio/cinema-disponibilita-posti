import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/cinema.dart';
import '../../core/storage/favorite_cinema_store.dart';

/// The bundled, static list of The Space locations (see tools/scrape_cinemas.py).
/// This is reference data that rarely changes, so it ships as an asset
/// instead of being fetched from the network on every launch.
final cinemaListProvider = FutureProvider<List<Cinema>>((ref) async {
  final raw = await rootBundle.loadString('assets/cinemas.json');
  final list = json.decode(raw) as List<dynamic>;
  return list.map((e) => Cinema.fromJson(e as Map<String, dynamic>)).toList();
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
/// order they were added.
final favoriteCinemasProvider = FutureProvider<List<Cinema>>((ref) async {
  final ids = await ref.watch(favoriteCinemaIdsProvider.future);
  final cinemas = await ref.watch(cinemaListProvider.future);
  final byId = {for (final c in cinemas) c.cinemaId: c};
  return [
    for (final id in ids)
      if (byId[id] != null) byId[id]!,
  ];
});

/// The currently active favorite cinema, resolved to its full [Cinema]
/// record - what the home screen actually shows showtimes for.
final activeCinemaProvider = FutureProvider<Cinema?>((ref) async {
  final id = await ref.watch(activeCinemaIdProvider.future);
  if (id == null) return null;
  final cinemas = await ref.watch(cinemaListProvider.future);
  for (final cinema in cinemas) {
    if (cinema.cinemaId == id) return cinema;
  }
  return null;
});
