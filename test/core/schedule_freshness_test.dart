import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/date/schedule_freshness.dart';

void main() {
  final day = DateTime(2026, 10, 20);

  group('isProgrammeFresh', () {
    test('today, downloaded before 11: fresh until 11, stale after', () {
      final fetched = DateTime(2026, 10, 20, 9);
      expect(
        isProgrammeFresh(
          day: day,
          fetchedAt: fetched,
          now: DateTime(2026, 10, 20, 10, 59),
        ),
        isTrue,
      );
      expect(
        isProgrammeFresh(
          day: day,
          fetchedAt: fetched,
          now: DateTime(2026, 10, 20, 11),
        ),
        isFalse,
      );
      expect(
        isProgrammeFresh(
          day: day,
          fetchedAt: fetched,
          now: DateTime(2026, 10, 20, 22),
        ),
        isFalse,
      );
    });

    test('today, downloaded at or after 11: fresh for the rest of the day', () {
      expect(
        isProgrammeFresh(
          day: day,
          fetchedAt: DateTime(2026, 10, 20, 11),
          now: DateTime(2026, 10, 20, 23, 59),
        ),
        isTrue,
      );
      expect(
        isProgrammeFresh(
          day: day,
          fetchedAt: DateTime(2026, 10, 20, 15),
          now: DateTime(2026, 10, 20, 16),
        ),
        isTrue,
      );
    });

    test('a future day seen today stays fresh until 11 of that day', () {
      final fetched = DateTime(2026, 10, 18, 20);
      expect(
        isProgrammeFresh(
          day: day,
          fetchedAt: fetched,
          now: DateTime(2026, 10, 19, 15),
        ),
        isTrue,
      );
      expect(
        isProgrammeFresh(
          day: day,
          fetchedAt: fetched,
          now: DateTime(2026, 10, 20, 10),
        ),
        isTrue,
      );
      expect(
        isProgrammeFresh(
          day: day,
          fetchedAt: fetched,
          now: DateTime(2026, 10, 20, 11, 1),
        ),
        isFalse,
      );
    });

    test('a download time in the future (clock moved back) is stale', () {
      expect(
        isProgrammeFresh(
          day: day,
          fetchedAt: DateTime(2026, 10, 20, 15),
          now: DateTime(2026, 10, 20, 12),
        ),
        isFalse,
      );
    });

    test('11:00 is local time, also on the DST change day', () {
      final dst = DateTime(2026, 10, 25); // clocks go back at 03:00
      expect(
        isProgrammeFresh(
          day: dst,
          fetchedAt: DateTime(2026, 10, 25, 4),
          now: DateTime(2026, 10, 25, 10, 59),
        ),
        isTrue,
      );
      expect(
        isProgrammeFresh(
          day: dst,
          fetchedAt: DateTime(2026, 10, 25, 4),
          now: DateTime(2026, 10, 25, 11),
        ),
        isFalse,
      );
    });
  });

  group('isShowingDatesFresh', () {
    test('needs a download from today, then follows the 11:00 rule', () {
      expect(
        isShowingDatesFresh(
          fetchedAt: DateTime(2026, 10, 19, 20),
          now: DateTime(2026, 10, 20, 8),
        ),
        isFalse,
      );
      expect(
        isShowingDatesFresh(
          fetchedAt: DateTime(2026, 10, 20, 8),
          now: DateTime(2026, 10, 20, 10),
        ),
        isTrue,
      );
      expect(
        isShowingDatesFresh(
          fetchedAt: DateTime(2026, 10, 20, 8),
          now: DateTime(2026, 10, 20, 12),
        ),
        isFalse,
      );
      expect(
        isShowingDatesFresh(
          fetchedAt: DateTime(2026, 10, 20, 12),
          now: DateTime(2026, 10, 20, 23),
        ),
        isTrue,
      );
    });
  });
}
