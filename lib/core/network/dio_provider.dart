import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const theSpaceBaseUrl = 'https://www.thespacecinema.it';

/// Bare HTTP client wiring: base URL + an in-memory cookie jar.
///
/// The public website's API (which this app talks to directly, the same
/// backend the mobile app and thespacecinema.it use) requires nothing more
/// than a normal browser-like cookie jar warmed up with one GET to the
/// homepage - no API key, no request signing, no certificate pinning were
/// found during reverse-engineering. Cookies are kept in memory only (not
/// persisted to disk): there's no login, so there's nothing worth surviving
/// an app restart, and re-warming on cold start is a single cheap GET.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: theSpaceBaseUrl,
      headers: const {
        'Accept': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/126.0 Safari/537.36',
      },
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  dio.interceptors.add(CookieManager(CookieJar()));
  return dio;
});
