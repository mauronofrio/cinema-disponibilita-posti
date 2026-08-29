import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/util/provider_ttl.dart';

// Exercises [keepAliveFor] directly against small, locally-defined test
// providers and a raw ProviderContainer - not the real seatMapProvider,
// which would need the whole chain-API/network stack mocked. This is the
// first ProviderContainer-level test in the suite: the seatMapProvider bug
// this pins (autoDispose silently missing, making the keepAlive/timer TTL
// idiom a complete no-op) has now shipped three times as a hand-copied
// inline idiom with no shared mechanism and no test watching the mechanism
// itself.
void main() {
  group('keepAliveFor', () {
    test('retains an autoDispose provider with no listeners, inside the TTL '
        'window - this is what makes the fire-and-forget '
        "ref.read(provider.future).ignore() seat-map prefetch work", () {
      var buildCount = 0;
      final provider = Provider.autoDispose<int>((ref) {
        buildCount++;
        keepAliveFor(ref, const Duration(milliseconds: 50));
        return buildCount;
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // `container.read` (like the app's `ref.read(...).ignore()`
      // prefetch) briefly listens and immediately unlistens, leaving zero
      // listeners the instant the call returns. Without `keepAliveFor`'s
      // `ref.keepAlive()` having already run synchronously inside
      // `create`, riverpod's normal autoDispose behavior would tear this
      // down right away.
      expect(container.read(provider), 1);
      expect(buildCount, 1);

      // Reading again, still with no listeners and still well inside the
      // TTL, must reuse the same build rather than recomputing it.
      expect(container.read(provider), 1);
      expect(buildCount, 1);
    });

    test(
      'releases the value once the TTL window elapses with no listeners',
      () {
        fakeAsync((async) {
          var buildCount = 0;
          final provider = Provider.autoDispose<int>((ref) {
            buildCount++;
            keepAliveFor(ref, const Duration(seconds: 5));
            return buildCount;
          });
          final container = ProviderContainer();
          addTearDown(container.dispose);

          expect(container.read(provider), 1);

          // Still inside the window: unchanged.
          async.elapse(const Duration(seconds: 4));
          expect(container.read(provider), 1);
          expect(buildCount, 1);

          // Past the window: the keepAliveFor timer fires and closes the
          // link: with no listeners left, riverpod is now free to dispose the
          // element, so the next read rebuilds it from scratch.
          async.elapse(const Duration(seconds: 2));
          expect(container.read(provider), 2);
          expect(buildCount, 2);
        });
      },
    );

    test('pins the .autoDispose requirement: the exact same keepAliveFor call, '
        'on a provider that is NOT autoDispose, never releases', () {
      fakeAsync((async) {
        var buildCount = 0;
        // This is Fix 1's exact bug shape (seatMapProvider was declared
        // as plain `FutureProvider.family`, not
        // `FutureProvider.autoDispose.family`): `ref.keepAlive()` /
        // `link.close()` only ever matter to an autoDispose provider - see
        // riverpod's ProviderElement.mayNeedDispose, which is a no-op
        // unless `provider.isAutoDispose`. So without `.autoDispose` here,
        // the value must survive forever, TTL timer or not.
        final provider = Provider<int>((ref) {
          buildCount++;
          keepAliveFor(ref, const Duration(seconds: 5));
          return buildCount;
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        expect(container.read(provider), 1);
        async.elapse(const Duration(seconds: 30));
        expect(container.read(provider), 1);
        expect(buildCount, 1);
      });
    });
  });
}
