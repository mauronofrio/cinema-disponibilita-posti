import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/models/film.dart';
import 'package:thespace_companion/features/showtimes/widgets/film_card.dart';

Session _session(String id, {bool withBadge = false}) {
  return Session(
    sessionId: id,
    startTime: DateTime(2026, 8, 24, 18),
    endTime: DateTime(2026, 8, 24, 20),
    screenName: 'Sala 1',
    isSoldOut: false,
    formattedPrice: null,
    isPriceVisible: false,
    attributes: withBadge
        ? [
            const SessionAttribute(
              name: 'Proiezione LASER 4K',
              attributeType: 'Session_Special',
              color: null,
            ),
          ]
        : const [],
    bookingPath: null,
  );
}

void main() {
  group('splitSessionsForPoster', () {
    test(
      'a handful of plain time-only sessions all fit beside the poster',
      () {
        final sessions = List.generate(4, (i) => _session('$i'));
        final split = splitSessionsForPoster(sessions);
        expect(split.beside, sessions);
        expect(split.below, isEmpty);
      },
    );

    test(
      'this is the actual regression case: once badged chips (roughly one '
      'per row, see The Space\'s Oceania with "Proiezione LASER 4K" on '
      'every showing) exceed the space next to a 96px poster, the rest '
      'overflow below instead of squeezing the whole card into a tall, '
      'mostly-empty-on-the-left column',
      () {
        final sessions = List.generate(
          10,
          (i) => _session('$i', withBadge: true),
        );
        final split = splitSessionsForPoster(sessions);
        // 2 rows beside the poster, 1 badged chip per row.
        expect(split.beside, sessions.take(2));
        expect(split.below, sessions.skip(2));
      },
    );

    test('plain chips pack several per row before spilling below', () {
      final sessions = List.generate(8, (i) => _session('$i'));
      final split = splitSessionsForPoster(sessions);
      // 2 rows beside the poster, 3 plain chips per row.
      expect(split.beside, sessions.take(6));
      expect(split.below, sessions.skip(6));
    });

    test('every session accounted for exactly once, beside or below', () {
      final sessions = [
        for (var i = 0; i < 5; i++) _session('plain-$i'),
        for (var i = 0; i < 5; i++) _session('badge-$i', withBadge: true),
      ];
      final split = splitSessionsForPoster(sessions);
      expect(split.beside.length + split.below.length, sessions.length);
      expect({...split.beside, ...split.below}, sessions.toSet());
    });
  });
}
