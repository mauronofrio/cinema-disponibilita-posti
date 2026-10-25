import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/date/schedule_freshness.dart';

void main() {
  group('isProgrammeFresh', () {
    test('fresh for 30 minutes after the download, then stale', () {
      final fetched = DateTime(2026, 10, 20, 15);
      expect(isProgrammeFresh(fetchedAt: fetched, now: fetched), isTrue);
      expect(
        isProgrammeFresh(
          fetchedAt: fetched,
          now: DateTime(2026, 10, 20, 15, 29, 59),
        ),
        isTrue,
      );
      expect(
        isProgrammeFresh(
          fetchedAt: fetched,
          now: DateTime(2026, 10, 20, 15, 30),
        ),
        isFalse,
      );
      expect(
        isProgrammeFresh(fetchedAt: fetched, now: DateTime(2026, 10, 21, 10)),
        isFalse,
      );
    });

    test('a download time in the future (clock moved back) is stale', () {
      expect(
        isProgrammeFresh(
          fetchedAt: DateTime(2026, 10, 20, 15),
          now: DateTime(2026, 10, 20, 12),
        ),
        isFalse,
      );
    });
  });

  group('isShowingDatesFresh', () {
    test('needs a download from today, less than 30 minutes old', () {
      expect(
        isShowingDatesFresh(
          fetchedAt: DateTime(2026, 10, 19, 23, 50),
          now: DateTime(2026, 10, 20, 0, 5),
        ),
        isFalse,
      );
      expect(
        isShowingDatesFresh(
          fetchedAt: DateTime(2026, 10, 20, 8),
          now: DateTime(2026, 10, 20, 8, 20),
        ),
        isTrue,
      );
      expect(
        isShowingDatesFresh(
          fetchedAt: DateTime(2026, 10, 20, 8),
          now: DateTime(2026, 10, 20, 8, 45),
        ),
        isFalse,
      );
    });
  });
}
