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

/// The user's saved favorite cinema id, or null if none has been picked yet.
final favoriteCinemaIdProvider = FutureProvider<String?>((ref) {
  return ref.watch(favoriteCinemaStoreProvider).read();
});

/// Resolves the favorite cinema id to its full [Cinema] record.
final favoriteCinemaProvider = FutureProvider<Cinema?>((ref) async {
  final id = await ref.watch(favoriteCinemaIdProvider.future);
  if (id == null) return null;
  final cinemas = await ref.watch(cinemaListProvider.future);
  for (final cinema in cinemas) {
    if (cinema.cinemaId == id) return cinema;
  }
  return null;
});
