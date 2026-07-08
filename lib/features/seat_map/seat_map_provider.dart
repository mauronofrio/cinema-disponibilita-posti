import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chains/chain_registry.dart';
import '../../core/models/cinema.dart';
import '../../core/models/film.dart';
import '../../core/models/seat_map.dart';

typedef SeatMapKey = (Cinema cinema, Session session);

/// Arguments passed via the router when navigating to the seat map screen -
/// the bits already known from the showtimes list, so the screen can render
/// its header instantly instead of waiting on the seat fetch for anything.
///
/// Carries every showing day for this film that's already known, not just
/// the one that was tapped: for The Space/UCI that's every day (their own
/// [ChainApi.getFilmsForDay] returns everything regardless of which day was
/// asked for, so this already covers the whole run and switching costs
/// nothing extra); for 18tickets-platform cinemas (RedCarpet, Multicinema
/// Galleria, ...) it's just the one day the user came from - switching to a
/// day not in here means [SeatMapScreen] fetches it lazily itself, keyed by
/// [filmId] to find the same film in that day's response.
class SeatMapArgs {
  const SeatMapArgs({
    required this.cinema,
    required this.filmId,
    required this.filmTitle,
    required this.showingGroups,
    required this.initialSessionId,
  });

  final Cinema cinema;
  final String filmId;
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

  final (cinema, session) = key;
  return ref.read(chainApiProvider(cinema.chain)).getSeatMap(cinema, session);
});
