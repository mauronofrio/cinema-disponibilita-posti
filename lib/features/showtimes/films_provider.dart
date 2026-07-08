import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chains/chain_registry.dart';
import '../../core/models/cinema.dart';
import '../../core/models/film.dart';

/// Films playing at a cinema with sessions on one specific day. The Space
/// and UCI fetch every day at once regardless (cheap for them, see their
/// own [ChainApi] implementations), so in practice this is served from one
/// shared cached response no matter which day is asked for; 18tickets-
/// platform cinemas (RedCarpet, Multicinema Galleria, ...) genuinely fetch
/// just this one day, lazily, only when it's actually asked for - see
/// PROJECT_NOTES.md for why (an aggressive per-IP rate limit on that
/// platform makes pre-fetching several days upfront unsafe).
///
/// Short in-memory TTL, never persisted. Not force-invalidated on day
/// rollover the way [showingDatesProvider] is: since this is keyed by the
/// literal calendar day rather than an abstract "today", there's no
/// mislabeling risk from a stale cache the way the original app bug worked -
/// worst case a specific day's session list is up to 7 minutes stale after
/// a rollover, which the TTL clears on its own shortly after.
final filmsForDayProvider =
    FutureProvider.family<List<Film>, (Cinema, DateTime)>((ref, args) async {
      final (cinema, day) = args;
      final link = ref.keepAlive();
      final timer = Timer(const Duration(minutes: 7), link.close);
      ref.onDispose(timer.cancel);
      return ref
          .read(chainApiProvider(cinema.chain))
          .getFilmsForDay(cinema, day);
    });
