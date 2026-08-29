import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chains/chain_registry.dart';
import '../../core/models/cinema.dart';
import '../../core/models/showing_date.dart';
import '../../core/util/provider_ttl.dart';

/// Which days the cinema has showings for. Kept in memory for a short TTL
/// (not persisted) - short enough that switching tabs doesn't re-fetch, long
/// enough to stay fresh. Never cached beyond process lifetime, and force-
/// invalidated on day rollover by the app shell (see app.dart).
final showingDatesProvider = FutureProvider.autoDispose
    .family<List<ShowingDate>, Cinema>((ref, cinema) async {
      keepAliveFor(ref, const Duration(minutes: 7));
      return ref.read(chainApiProvider(cinema.chain)).getShowingDates(cinema);
    });
