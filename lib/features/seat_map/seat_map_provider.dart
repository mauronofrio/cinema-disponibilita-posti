import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chains/chain_registry.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/models/cinema.dart';
import '../../core/models/film.dart';
import '../../core/models/seat_map.dart';
import '../../core/network/api_client.dart' show ApiException;
import '../../core/util/provider_ttl.dart';

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
    required this.posterImageSrc,
    required this.runningTime,
    required this.showingGroups,
    required this.initialSessionId,
  });

  final Cinema cinema;
  final String filmId;
  final String filmTitle;
  final String? posterImageSrc;
  final int? runningTime;
  final List<ShowingGroup> showingGroups;
  final String initialSessionId;
}

/// Seat availability for one session. Deliberately short-lived (unlike the
/// showtimes/films caches): occupancy is the most volatile data in the app,
/// so this TTL exists only to make an accidental back-then-forward
/// navigation instant, never to serve minutes-old booking state.
///
/// `autoDispose` matters here in a way it doesn't for its siblings: without
/// it, [keepAliveFor]'s `link.close()` after the TTL would be a no-op (a
/// keep-alive link only ever *prevents* a disposal that `autoDispose` would
/// otherwise schedule), so occupancy would stay cached - and a transient
/// fetch error along with it - for the rest of the app's process lifetime.
/// The two fire-and-forget prefetch call sites
/// (`ref.read(seatMapProvider(...).future).ignore()` in film_card.dart and
/// seat_map_screen.dart) still work with `autoDispose`: [keepAliveFor] runs
/// synchronously inside `create`, before Riverpod ever gets a chance to
/// notice the listener count is zero, so the keep-alive link is already in
/// place by the time there would be anything to dispose.
final seatMapProvider = FutureProvider.autoDispose.family<SeatMap, SeatMapKey>((
  ref,
  key,
) async {
  keepAliveFor(ref, const Duration(seconds: 45));

  final (cinema, session) = key;
  final seatMap = await ref
      .read(chainApiProvider(cinema.chain))
      .getSeatMap(cinema, session);

  // A room with no seats at all is missing data, not an empty screening -
  // but nothing downstream could tell the difference: the grid renders
  // blank and OccupancySummary reads "Occupati 0/0 · 0%", which a user
  // reasonably takes as "wide open, plenty of seats". Silently wrong is
  // worse than an error here, since seat availability is the one thing
  // this app exists to answer.
  //
  // This is a real backend state, not a hypothetical: some venues return
  // `idsala: 0, capienza: 0, posti: []` for every performance (see
  // PROJECT_NOTES.md), and the parsers happily turn that into a valid but
  // empty SeatMap. Guarded here rather than in each of the four parsers
  // because this is the single point every chain's seat map passes
  // through.
  if (seatMap.rows.isEmpty) {
    throw ApiException(AppLocalizations.current.seatsLoadError);
  }
  return seatMap;
});
