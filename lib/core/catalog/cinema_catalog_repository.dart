import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../date/clock.dart';
import '../models/cinema.dart';
import 'cinema_catalog_parser.dart';

/// The cinema list: bundled in the app, and refreshed from the very same
/// file on GitHub at most once a day, so a cinema can be added with a
/// commit instead of a release. Every downloaded list is validated before
/// use and the last good one is kept - a bad push or a network problem can
/// never leave a user with fewer cinemas than they had.
class CinemaCatalogRepository {
  CinemaCatalogRepository({
    required Dio dio,
    required Clock clock,
    required Future<String> Function() loadBundled,
  }) : _dio = dio,
       _clock = clock,
       _loadBundled = loadBundled;

  static const remoteUrl =
      'https://raw.githubusercontent.com/mauronofrio/cinema-disponibilita-posti/master/assets/cinemas.json';
  static const checkInterval = Duration(hours: 24);

  static const _bodyKey = 'cinema_catalog_body';
  static const _etagKey = 'cinema_catalog_etag';
  static const _checkedAtKey = 'cinema_catalog_checked_at';
  static const _appVersionKey = 'cinema_catalog_app_version';

  final Dio _dio;
  final Clock _clock;
  final Future<String> Function() _loadBundled;

  Future<List<Cinema>> _bundled(String appVersion) async =>
      parseCinemaCatalog(await _loadBundled(), appVersion: appVersion);

  /// Null when [body] must not replace what the user has: unparseable,
  /// duplicate keys, or fewer than half the bundled cinemas (a truncated or
  /// emptied file pushed by mistake).
  List<Cinema>? _accept(String body, String appVersion, int bundledCount) {
    final List<Cinema> cinemas;
    try {
      cinemas = parseCinemaCatalog(body, appVersion: appVersion);
    } on FormatException {
      return null;
    }
    final keys = {for (final c in cinemas) '${c.chain.name}:${c.cinemaId}'};
    if (keys.length != cinemas.length) return null;
    if (cinemas.length * 2 < bundledCount) return null;
    return cinemas;
  }

  /// A new app version ships a bundled list at least as fresh as any cache
  /// an older version downloaded - so a cache stamped with a different
  /// version is dropped. No stamp at all just means "nothing cached yet".
  Future<void> _dropCacheFromOtherVersion(
    SharedPreferences prefs,
    String appVersion,
  ) async {
    final stamped = prefs.getString(_appVersionKey);
    if (stamped != null && stamped != appVersion) await _clear(prefs);
  }

  Future<List<Cinema>> load({required String appVersion}) async {
    final bundled = await _bundled(appVersion);
    final prefs = await SharedPreferences.getInstance();
    await _dropCacheFromOtherVersion(prefs, appVersion);
    final cached = prefs.getString(_bodyKey);
    if (cached == null) return bundled;
    return _accept(cached, appVersion, bundled.length) ?? bundled;
  }

  /// Runs fire-and-forget from the provider, so it must never throw: any
  /// failure (network, storage, parsing) just means "no new list".
  Future<bool> refreshIfStale({required String appVersion}) async {
    try {
      return await _refreshIfStale(appVersion);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _refreshIfStale(String appVersion) async {
    final prefs = await SharedPreferences.getInstance();
    await _dropCacheFromOtherVersion(prefs, appVersion);
    final checkedAt = DateTime.tryParse(prefs.getString(_checkedAtKey) ?? '');
    final now = _clock.now();
    if (checkedAt != null && now.difference(checkedAt) < checkInterval) {
      return false;
    }
    final etag = prefs.getString(_etagKey);
    final Response<String> response;
    try {
      response = await _dio.get<String>(
        remoteUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'If-None-Match': ?etag},
          validateStatus: (s) => s != null && s < 600,
        ),
      );
    } on DioException {
      return false; // offline: try again next launch, keep what we have
    }
    if (response.statusCode == 304) {
      await prefs.setString(_checkedAtKey, now.toIso8601String());
      return false;
    }
    if (response.statusCode != 200) return false;
    final bundled = await _bundled(appVersion);
    final body = response.data ?? '';
    final accepted = _accept(body, appVersion, bundled.length);
    await prefs.setString(_checkedAtKey, now.toIso8601String());
    await prefs.setString(_appVersionKey, appVersion);
    if (accepted == null) return false;
    await prefs.setString(_bodyKey, body);
    final newEtag = response.headers.value('etag');
    if (newEtag != null) await prefs.setString(_etagKey, newEtag);
    return true;
  }

  Future<void> _clear(SharedPreferences prefs) async {
    await prefs.remove(_bodyKey);
    await prefs.remove(_etagKey);
    await prefs.remove(_checkedAtKey);
    await prefs.remove(_appVersionKey);
  }
}

final cinemaCatalogRepositoryProvider = Provider<CinemaCatalogRepository>((ref) {
  return CinemaCatalogRepository(
    dio: Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
      ),
    ),
    clock: ref.watch(clockProvider),
    loadBundled: () => rootBundle.loadString('assets/cinemas.json'),
  );
});
