import '../date/clock.dart';

/// One cached value plus the [Clock] time it was produced at, so a
/// [TtlCache] can tell a fresh entry from a stale one without trusting
/// `DateTime.now()` directly (see [Clock]'s own doc for why that's a hard
/// rule in this codebase).
class _Entry<V> {
  _Entry(this.value, this.storedAt);

  final V value;
  final DateTime storedAt;
}

/// A small, generic "map keyed by id, each entry good for [ttl]" cache -
/// the same pattern `WebticChainApi` and `EighteenTicketsChainApi` used to
/// hand-roll independently (a `Map` plus a `fetchedAt` timestamp field,
/// checked against a magic-number `Duration` at every read), pulled out
/// once since both chains need exactly this and nothing more. Each caller
/// keeps its own [TtlCache] instance and its own tuned [ttl] (5 minutes vs
/// 20) - only the mechanism is shared here, not the tuning.
class TtlCache<K, V> {
  TtlCache(this._clock, this.ttl);

  final Clock _clock;
  final Duration ttl;
  final _entries = <K, _Entry<V>>{};

  /// The still-fresh value stored for [key], or `null` if nothing was ever
  /// stored or the entry has aged past [ttl].
  V? get(K key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (_clock.now().difference(entry.storedAt) >= ttl) return null;
    return entry.value;
  }

  void set(K key, V value) {
    _entries[key] = _Entry(value, _clock.now());
  }
}
