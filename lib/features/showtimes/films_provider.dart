import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/film.dart';
import '../../core/network/api_client.dart';

/// Films playing at a cinema, with all their showingGroups (every day in one
/// response) - short in-memory TTL, never persisted, invalidated on day
/// rollover by the app shell (see app.dart).
final filmsForCinemaProvider = FutureProvider.family<List<Film>, String>((
  ref,
  cinemaId,
) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 7), link.close);
  ref.onDispose(timer.cancel);
  return ref.read(apiClientProvider).getFilmsForCinema(cinemaId);
});
