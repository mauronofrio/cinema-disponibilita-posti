import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../date/clock.dart';
import '../models/cinema.dart';
import 'cinema_catalog_parser.dart';

/// The cinema list: bundled in the app, and refreshed from the very same
/// file on GitHub at most once a day, so a cinema can be added with a
/// commit instead of a release.
///
/// A downloaded list is used only if it parses as a JSON list, has no
/// duplicate `chain:cinemaId` keys and keeps at least half as many usable
/// entries as the bundled list; otherwise the last good list (cache, else
/// bundled) stays. An accepted list is then merged with the bundled one:
/// every bundled cinema whose `chain:cinemaId` key appears nowhere in the
/// *raw* remote JSON is added back, so a stale or partial remote file can
/// never take away a cinema this app shipped with. For a key the remote
/// does contain, the remote entry wins - even when it hides that cinema
/// (`minAppVersion` too new, an unknown value, a malformed field): that is
/// the deliberate way to withdraw a cinema from installed apps.
///
/// Any 4xx (moved file, rate limit) counts as a completed check, so it costs
/// one request a day; network errors and 5xx retry on the next launch.
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

  /// The refresh currently running, shared by concurrent callers.
  Future<bool>? _inFlight;

  Future<List<Cinema>> _bundled(String appVersion) async =>
      parseCinemaCatalog(await _loadBundled(), appVersion: appVersion);

  static String _key(Cinema c) => '${c.chain.name}:${c.cinemaId}';

  /// Every `chain:cinemaId` key in the raw remote JSON, before any entry is
  /// filtered out - read leniently: a missing/null `chain` is The Space, any
  /// other value (even a malformed one) is used as written.
  static Set<String> _rawKeys(String body) {
    final decoded = jsonDecode(body) as List<dynamic>;
    return {
      for (final raw in decoded)
        if (raw is Map)
          '${raw['chain'] ?? CinemaChain.theSpace.name}:${raw['cinemaId']}',
    };
  }

  /// Null when [body] must not replace what the user has: unparseable,
  /// duplicate keys, or fewer than half the bundled cinemas (a truncated or
  /// emptied file pushed by mistake). Otherwise the remote cinemas plus every
  /// bundled cinema whose key the raw remote list doesn't mention.
  List<Cinema>? _accept(String body, String appVersion, List<Cinema> bundled) {
    final List<Cinema> cinemas;
    final Set<String> rawKeys;
    try {
      cinemas = parseCinemaCatalog(body, appVersion: appVersion);
      rawKeys = _rawKeys(body);
    } on FormatException {
      return null;
    }
    final keys = {for (final c in cinemas) _key(c)};
    if (keys.length != cinemas.length) return null;
    if (cinemas.length * 2 < bundled.length) return null;
    return [
      ...cinemas,
      for (final c in bundled)
        if (!rawKeys.contains(_key(c))) c,
    ];
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
    return _accept(cached, appVersion, bundled) ?? bundled;
  }

  /// Runs fire-and-forget from the provider, so it must never throw: any
  /// failure (network, storage, parsing) just means "no new list". Callers
  /// arriving while a refresh is running share it (one request). True means
  /// a new list was stored: [load] returns it, merged with the bundled one.
  Future<bool> refreshIfStale({required String appVersion}) {
    return _inFlight ??= _guardedRefresh(appVersion).whenComplete(() {
      _inFlight = null;
    });
  }

  Future<bool> _guardedRefresh(String appVersion) async {
    try {
      return await _refreshIfStale(appVersion);
    } catch (_) {
      return false;
    }
  }

  Future<void> _stampChecked(
    SharedPreferences prefs,
    DateTime now,
    String appVersion,
  ) async {
    await prefs.setString(_checkedAtKey, now.toIso8601String());
    await prefs.setString(_appVersionKey, appVersion);
  }

  Future<bool> _refreshIfStale(String appVersion) async {
    final prefs = await SharedPreferences.getInstance();
    await _dropCacheFromOtherVersion(prefs, appVersion);
    final checkedAt = DateTime.tryParse(prefs.getString(_checkedAtKey) ?? '');
    final now = _clock.now();
    if (checkedAt != null) {
      final age = now.difference(checkedAt);
      // A negative age means the clock went backwards: treat it as stale
      // rather than trusting a check stamped "in the future".
      if (!age.isNegative && age < checkInterval) return false;
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
    final status = response.statusCode ?? 0;
    // 304, and any 4xx (moved file, rate limit): the check is done for today.
    if (status == 304 || (status >= 400 && status < 500)) {
      await _stampChecked(prefs, now, appVersion);
      return false;
    }
    if (status != 200) return false; // 5xx: retry on the next launch
    final bundled = await _bundled(appVersion);
    final body = response.data ?? '';
    final accepted = _accept(body, appVersion, bundled);
    await _stampChecked(prefs, now, appVersion);
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
