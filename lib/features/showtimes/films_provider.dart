import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chains/chain_registry.dart';
import '../../core/models/cinema.dart';
import '../../core/models/film.dart';

/// Films playing at a cinema, with all their showingGroups (every day in one
/// response for The Space; UCI has no such endpoint, so its [ChainApi]
/// fetches every published day itself and merges them into the same shape) -
/// short in-memory TTL, never persisted, invalidated on day rollover by the
/// app shell (see app.dart).
final filmsForCinemaProvider = FutureProvider.family<List<Film>, Cinema>((
  ref,
  cinema,
) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 7), link.close);
  ref.onDispose(timer.cancel);
  return ref.read(chainApiProvider(cinema.chain)).getFilmsForCinema(cinema);
});
