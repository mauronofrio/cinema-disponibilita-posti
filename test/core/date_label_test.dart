import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/date/day_label.dart';

void main() {
  group('resolveDayLabel', () {
    test('same calendar day is today, regardless of time of day', () {
      final now = DateTime(2026, 7, 6, 23, 59, 59);
      final showing = DateTime(2026, 7, 6, 0, 0, 1);
      expect(resolveDayLabel(showing, now), DayLabelKind.today);
    });

    test('just after midnight rolls over to a new "today"', () {
      final now = DateTime(2026, 7, 7, 0, 0, 1);
      final yesterdayShowing = DateTime(2026, 7, 6);
      expect(resolveDayLabel(yesterdayShowing, now), DayLabelKind.other);
    });

    test('this is the actual regression case for the official app\'s bug: '
        'a showing dated "today" must not still read as today once the '
        'device date has advanced, even by one second past midnight', () {
      final showingFromYesterday = DateTime(2026, 7, 6);
      final nowTomorrow = DateTime(2026, 7, 7, 0, 0, 1);
      expect(
        resolveDayLabel(showingFromYesterday, nowTomorrow),
        isNot(DayLabelKind.today),
      );
    });

    test('next calendar day is tomorrow', () {
      final now = DateTime(2026, 7, 6, 10);
      final showing = DateTime(2026, 7, 7, 23);
      expect(resolveDayLabel(showing, now), DayLabelKind.tomorrow);
    });

    test('two days ahead is other', () {
      final now = DateTime(2026, 7, 6);
      final showing = DateTime(2026, 7, 8);
      expect(resolveDayLabel(showing, now), DayLabelKind.other);
    });

    test('a day in the past is other, not today', () {
      final now = DateTime(2026, 7, 6);
      final showing = DateTime(2026, 7, 5);
      expect(resolveDayLabel(showing, now), DayLabelKind.other);
    });

    test('month rollover: last day of month vs first of next', () {
      final now = DateTime(2026, 7, 31);
      final showing = DateTime(2026, 8, 1);
      expect(resolveDayLabel(showing, now), DayLabelKind.tomorrow);
    });

    test('year rollover: Dec 31 vs Jan 1', () {
      final now = DateTime(2026, 12, 31);
      final showing = DateTime(2027, 1, 1);
      expect(resolveDayLabel(showing, now), DayLabelKind.tomorrow);
    });
  });

  group('todayKey', () {
    test('formats as yyyy-MM-dd with zero padding', () {
      expect(todayKey(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('two different calendar days produce different keys', () {
      final a = todayKey(DateTime(2026, 7, 6, 23, 59));
      final b = todayKey(DateTime(2026, 7, 7, 0, 1));
      expect(a, isNot(equals(b)));
    });

    test('same calendar day at different times produces the same key', () {
      final a = todayKey(DateTime(2026, 7, 6, 0, 0));
      final b = todayKey(DateTime(2026, 7, 6, 23, 59));
      expect(a, equals(b));
    });
  });
}
