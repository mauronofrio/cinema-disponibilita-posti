import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/showing_date.dart';
import '../../core/network/api_client.dart';

/// Which days the cinema has showings for. Kept in memory for a short TTL
/// (not persisted) - short enough that switching tabs doesn't re-fetch, long
/// enough to stay fresh. Never cached beyond process lifetime, and force-
/// invalidated on day rollover by the app shell (see app.dart).
final showingDatesProvider = FutureProvider.family<List<ShowingDate>, String>((
  ref,
  cinemaId,
) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 7), link.close);
  ref.onDispose(timer.cancel);
  return ref.read(apiClientProvider).getShowingDates(cinemaId);
});
