import 'dart:async';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/film.dart';
import '../../core/models/seat_map.dart';
import '../../core/network/api_client.dart';

typedef SeatMapKey = (String cinemaId, String sessionId);

/// Arguments passed via the router when navigating to the seat map screen -
/// the bits already known from the showtimes list, so the screen can render
/// its header instantly instead of waiting on the seat fetch for anything.
///
/// Carries every showing day for this film, not just the one that was
/// tapped: `getFilmsForCinema` already returns every day's sessions in one
/// response (see films_provider.dart), so letting the screen itself switch
/// day and showtime costs no extra request at all.
class SeatMapArgs {
  const SeatMapArgs({
    required this.cinemaId,
    required this.filmTitle,
    required this.showingGroups,
    required this.initialSessionId,
  });

  final String cinemaId;
  final String filmTitle;
  final List<ShowingGroup> showingGroups;
  final String initialSessionId;
}

/// Seat availability for one session. Deliberately short-lived (unlike the
/// showtimes/films caches): occupancy is the most volatile data in the app,
/// so this TTL exists only to make an accidental back-then-forward
/// navigation instant, never to serve minutes-old booking state.
final seatMapProvider = FutureProvider.family<SeatMap, SeatMapKey>((
  ref,
  key,
) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 45), link.close);
  ref.onDispose(timer.cancel);

  final raw = await ref.read(apiClientProvider).getSeatMapJson(key.$1, key.$2);
  // Both jsonDecode and the model mapping happen off the UI isolate: the
  // response can be several hundred KB, dominated by redundant per-seat
  // metadata that SeatMap.fromApiResponseJson also strips down to just what
  // the grid needs.
  return compute(SeatMap.fromApiResponseJson, raw);
});
