import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/update/update_checker.dart';

void main() {
  group('isNewerVersion', () {
    test('plain numeric compare across all three segments', () {
      expect(isNewerVersion(current: '1.0.0', latest: '1.0.1'), isTrue);
      expect(isNewerVersion(current: '1.0.0', latest: '1.1.0'), isTrue);
      expect(isNewerVersion(current: '1.0.0', latest: '2.0.0'), isTrue);
      expect(isNewerVersion(current: '1.0.0', latest: '1.0.0'), isFalse);
      expect(isNewerVersion(current: '1.1.0', latest: '1.0.9'), isFalse);
    });

    test('tolerates the real tag formats used on this repo', () {
      // The first actual release was tagged "V1.0.0" - uppercase V.
      expect(isNewerVersion(current: '1.0.0', latest: 'V1.0.0'), isFalse);
      expect(isNewerVersion(current: '1.0.0', latest: 'V1.1.0'), isTrue);
      expect(isNewerVersion(current: '1.0.0', latest: 'v1.1.0'), isTrue);
    });

    test('ignores pubspec-style build/suffix parts', () {
      expect(isNewerVersion(current: '1.0.0+1', latest: '1.0.0'), isFalse);
      expect(isNewerVersion(current: '1.0.0+1', latest: '1.0.1-beta'), isTrue);
    });

    test('missing segments count as zero, numerically not lexically', () {
      expect(isNewerVersion(current: '1.0.5', latest: '1.1'), isTrue);
      expect(isNewerVersion(current: '1.10.0', latest: '1.9.9'), isFalse);
    });
  });

  group('parseLatestRelease', () {
    test('prefers the APK asset\'s direct download URL', () {
      const body = '''
      {
        "tag_name": "V1.0.0",
        "html_url": "https://github.com/mauronofrio/cinema-disponibilita-posti/releases/tag/V1.0.0",
        "assets": [
          {"name": "checksums.txt", "browser_download_url": "https://example.com/checksums.txt"},
          {"name": "CinemaDisponibilitaPosti.apk", "browser_download_url": "https://example.com/app.apk"}
        ]
      }
      ''';
      final release = parseLatestRelease(body)!;
      expect(release.version, 'V1.0.0');
      expect(release.downloadUrl, 'https://example.com/app.apk');
    });

    test('falls back to the release page when no APK asset exists', () {
      const body = '''
      {
        "tag_name": "V1.0.0",
        "html_url": "https://example.com/releases/tag/V1.0.0",
        "assets": []
      }
      ''';
      expect(
        parseLatestRelease(body)!.downloadUrl,
        'https://example.com/releases/tag/V1.0.0',
      );
    });

    test('returns null for a body without a tag (e.g. a 404 error payload)', () {
      expect(
        parseLatestRelease('{"message": "Not Found", "status": "404"}'),
        isNull,
      );
    });
  });
}
