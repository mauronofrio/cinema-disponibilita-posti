import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chains/chain_registry.dart';
import '../../core/date/clock.dart';
import '../../core/date/schedule_freshness.dart';
import '../../core/models/cinema.dart';
import '../../core/models/showing_date.dart';
import '../../core/storage/schedule_cache_store.dart';
import '../../core/util/provider_ttl.dart';

/// Which days the cinema has showings for. Saved on the device and reused
/// while [isShowingDatesFresh] says so (downloaded today, and after 11:00 or
/// it isn't 11:00 yet); force-invalidated on day rollover by the app shell
/// (see app.dart), where the saved copy is then stale by that same rule.
final showingDatesProvider = FutureProvider.autoDispose
    .family<List<ShowingDate>, Cinema>((ref, cinema) async {
      keepAliveFor(ref, const Duration(minutes: 7));
      final store = ref.read(scheduleCacheStoreProvider);
      final clock = ref.read(clockProvider);
      final cached = await store.readShowingDates(cinema);
      if (cached != null &&
          isShowingDatesFresh(fetchedAt: cached.fetchedAt, now: clock.now())) {
        return cached.data;
      }
      final dates = await ref
          .read(chainApiProvider(cinema.chain))
          .getShowingDates(cinema);
      await store.writeShowingDates(cinema, dates, clock.now());
      return dates;
    });
