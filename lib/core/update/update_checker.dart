import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The app is distributed as a bare APK from GitHub releases, not through a
/// store - without this check a user who installed it once would simply
/// never learn an update exists. The releases API is public and unauthenticated
/// (60 requests/hour/IP rate limit, far above one check per app start).
const _latestReleaseUrl =
    'https://api.github.com/repos/mauronofrio/cinema-disponibilita-posti/releases/latest';

/// A newer release than the running app, ready to offer to the user.
class AvailableUpdate {
  const AvailableUpdate({
    required this.latestVersion,
    required this.currentVersion,
    required this.downloadUrl,
  });

  final String latestVersion;
  final String currentVersion;

  /// The APK asset's own direct download URL when the release has one,
  /// otherwise the release page - either way `launchUrl` opens it in the
  /// browser and Android takes over the download/install from there (no
  /// REQUEST_INSTALL_PACKAGES permission needed, unlike an in-app installer).
  final String downloadUrl;
}

/// One release as the GitHub API describes it, trimmed to what the update
/// check needs. Kept separate from [AvailableUpdate] so parsing stays a pure
/// String -> object function, testable without any platform/package-info
/// plumbing.
class LatestRelease {
  const LatestRelease({required this.version, required this.downloadUrl});

  final String version;
  final String downloadUrl;
}

/// `null` for anything that doesn't look like a release (e.g. a 404 body
/// when no release exists yet) rather than throwing - the caller treats
/// every failure mode as "no update", never as an error to surface.
LatestRelease? parseLatestRelease(String responseBody) {
  final decoded = json.decode(responseBody);
  if (decoded is! Map<String, dynamic>) return null;
  final tag = decoded['tag_name'] as String?;
  if (tag == null || tag.isEmpty) return null;

  String? apkUrl;
  for (final asset in (decoded['assets'] as List<dynamic>? ?? const [])) {
    if (asset is! Map<String, dynamic>) continue;
    final name = (asset['name'] as String?) ?? '';
    if (name.toLowerCase().endsWith('.apk')) {
      apkUrl = asset['browser_download_url'] as String?;
      break;
    }
  }
  return LatestRelease(
    version: tag,
    downloadUrl: apkUrl ?? (decoded['html_url'] as String? ?? ''),
  );
}

/// Numeric compare of dotted versions, tolerant of the real-world tag
/// formats already seen on this repo: a leading `v` OR `V` (the first
/// release was tagged "V1.0.0", uppercase), and pubspec-style `+build` /
/// `-suffix` parts, which are ignored. Missing segments count as 0, so
/// "1.1" > "1.0.5".
bool isNewerVersion({required String current, required String latest}) {
  List<int> parse(String v) {
    final core = v
        .trim()
        .replaceFirst(RegExp(r'^v', caseSensitive: false), '')
        .split('+')
        .first
        .split('-')
        .first;
    return core.split('.').map((part) => int.tryParse(part) ?? 0).toList();
  }

  final currentParts = parse(current);
  final latestParts = parse(latest);
  for (var i = 0; i < 3; i++) {
    final c = i < currentParts.length ? currentParts[i] : 0;
    final l = i < latestParts.length ? latestParts[i] : 0;
    if (l != c) return l > c;
  }
  return false;
}

/// One check per app start (plain FutureProvider, cached for the session).
/// Resolves to `null` both when already up to date and on ANY failure
/// (offline, rate-limited, no release yet, malformed response): an update
/// check is a courtesy, never something worth an error state in the UI.
final updateCheckProvider = FutureProvider<AvailableUpdate?>((ref) async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    final response = await dio.get<String>(
      _latestReleaseUrl,
      options: Options(
        responseType: ResponseType.plain,
        headers: {'Accept': 'application/vnd.github+json'},
      ),
    );
    final release = parseLatestRelease(response.data!);
    if (release == null || release.downloadUrl.isEmpty) return null;
    if (!isNewerVersion(
      current: packageInfo.version,
      latest: release.version,
    )) {
      return null;
    }
    return AvailableUpdate(
      latestVersion: release.version.replaceFirst(
        RegExp(r'^v', caseSensitive: false),
        '',
      ),
      currentVersion: packageInfo.version,
      downloadUrl: release.downloadUrl,
    );
  } catch (_) {
    return null;
  }
});
