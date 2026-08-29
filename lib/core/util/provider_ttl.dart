import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps an `autoDispose` provider's value alive for [duration] after it
/// stops having listeners, instead of disposing immediately - the shared
/// "cache this for a little while" idiom used by the short-TTL providers in
/// this app (seat maps, showing dates, films-for-day).
///
/// Call this once, synchronously, at the top of the provider's `create`
/// callback - synchronously matters because it's what makes a
/// `ref.read(provider.future).ignore()`-style prefetch (no listener at all)
/// still stick around instead of being disposed the instant the read
/// settles: [Ref.keepAlive] registers a link before Riverpod ever gets a
/// chance to notice the listener count is zero.
///
/// Only meaningful on an `autoDispose` provider - on a provider that isn't
/// `autoDispose`, [Ref.keepAlive] is already a no-op (nothing to dispose
/// early), so calling this here is harmless but pointless.
void keepAliveFor(Ref ref, Duration duration) {
  final link = ref.keepAlive();
  final timer = Timer(duration, link.close);
  ref.onDispose(timer.cancel);
}
