import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chains/chain_registry.dart';
import '../../core/date/clock.dart';
import '../../core/date/schedule_freshness.dart';
import '../../core/models/cinema.dart';
import '../../core/models/film.dart';
import '../../core/storage/schedule_cache_store.dart';
import '../../core/util/provider_ttl.dart';

/// Films playing at a cinema with sessions on one specific day. The Space
/// and UCI fetch every day at once regardless (cheap for them, see their
/// own [ChainApi] implementations), so in practice this is served from one
/// shared cached response no matter which day is asked for; 18tickets-
/// platform cinemas (RedCarpet, Multicinema Galleria, ...) genuinely fetch
/// just this one day, lazily, only when it's actually asked for - see
/// PROJECT_NOTES.md for why (an aggressive per-IP rate limit on that
/// platform makes pre-fetching several days upfront unsafe).
///
/// Saved on the device (ScheduleCacheStore) and served from there while
/// [isProgrammeFresh] says so (less than 30 minutes old); after that it is
/// downloaded again the next time someone opens that day, or when the app
/// comes back to the foreground (see app.dart). Pull-to-refresh forgets the
/// saved copy first (see showtimes_home_screen.dart).
final filmsForDayProvider = FutureProvider.autoDispose
    .family<List<Film>, (Cinema, DateTime)>((ref, args) async {
      final (cinema, day) = args;
      keepAliveFor(ref, const Duration(minutes: 7));
      final store = ref.read(scheduleCacheStoreProvider);
      final clock = ref.read(clockProvider);
      final cached = await store.readFilms(cinema, day);
      if (cached != null &&
          isProgrammeFresh(fetchedAt: cached.fetchedAt, now: clock.now())) {
        return cached.data;
      }
      final films = await ref
          .read(chainApiProvider(cinema.chain))
          .getFilmsForDay(cinema, day);
      await store.writeFilms(cinema, day, films, clock.now());
      return films;
    });
