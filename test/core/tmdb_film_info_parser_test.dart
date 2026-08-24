import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/chains/tmdb/tmdb_film_info_parser.dart';

void main() {
  group('cleanTitleForSearch', () {
    test('a plain title with no disambiguation suffix is unchanged', () {
      expect(cleanTitleForSearch('OCEANIA (LIVE ACTION 2026)'),
          'OCEANIA (LIVE ACTION 2026)');
    });

    test(
      'this is the actual regression case: the " · {label}" suffix this app '
      'itself appends to disambiguate duplicate 18tickets titles (see '
      'eighteen_tickets_film_parser.dart) is stripped before searching, '
      'since TMDb has never heard of "OCEANIA (MOANA) · Sing-Along"',
      () {
        expect(
          cleanTitleForSearch('OCEANIA (MOANA) · 🎤 Sing-Along'),
          'OCEANIA (MOANA)',
        );
      },
    );
  });

  group('parseTmdbSearchResult', () {
    test('reads id and overview off the first result', () {
      final body = File(
        'test/fixtures/tmdb_search_movie_sample.json',
      ).readAsStringSync();
      final result = parseTmdbSearchResult(body);
      expect(result, isNotNull);
      expect(result!.id, 1241436);
      expect(result.overview, contains('Vaiana'));
    });

    test('an empty results list returns null, not a crash', () {
      final body = File(
        'test/fixtures/tmdb_search_movie_empty_sample.json',
      ).readAsStringSync();
      expect(parseTmdbSearchResult(body), isNull);
    });
  });

  group('parseTmdbTrailerKey', () {
    test(
      'prefers the official YouTube Trailer over a non-official Teaser and '
      'over a Trailer hosted on a different site',
      () {
        final body = File(
          'test/fixtures/tmdb_movie_videos_sample.json',
        ).readAsStringSync();
        expect(parseTmdbTrailerKey(body), 'abc123xyz');
      },
    );

    test('no YouTube video at all returns null, not a crash', () {
      final body = File(
        'test/fixtures/tmdb_movie_videos_no_youtube_sample.json',
      ).readAsStringSync();
      expect(parseTmdbTrailerKey(body), isNull);
    });
  });
}
