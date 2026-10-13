import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/network/api_client.dart';

/// Stands in for thespacecinema.it, reproducing the behaviour confirmed live
/// on 13 Oct 2026: the homepage hands out a `microservicesToken` cookie, the
/// API answers 401 with an empty body whenever that token is missing or no
/// longer valid, and API responses never renew it - only another homepage
/// visit does.
class _FakeTheSpaceServer implements HttpClientAdapter {
  int _tokenGeneration = 0;
  int homepageVisits = 0;
  int apiRequests = 0;

  /// The server refusing even freshly-issued cookies (e.g. blocking us).
  bool rejectEverything = false;

  /// What the real token's 12h lifetime does to a long-running app process.
  void expireToken() => _tokenGeneration++;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/') {
      homepageVisits++;
      return ResponseBody.fromString(
        '<html></html>',
        200,
        headers: {
          'set-cookie': ['microservicesToken=gen$_tokenGeneration; Path=/'],
        },
      );
    }
    apiRequests++;
    final cookie = options.headers['cookie'] as String? ?? '';
    if (rejectEverything ||
        !cookie.contains('microservicesToken=gen$_tokenGeneration')) {
      return ResponseBody.fromString('', 401);
    }
    return ResponseBody.fromString(
      json.encode({'result': <Object>[]}),
      200,
      headers: {
        'content-type': ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(TheSpaceApiClient, _FakeTheSpaceServer) _client() {
  final server = _FakeTheSpaceServer();
  final dio = Dio(BaseOptions(baseUrl: 'https://www.thespacecinema.it'))
    ..httpClientAdapter = server
    ..interceptors.add(CookieManager(CookieJar()));
  return (TheSpaceApiClient(dio), server);
}

void main() {
  group('TheSpaceApiClient', () {
    test(
      'warms up once, then reuses the cookies while they are valid',
      () async {
        final (client, server) = _client();

        await client.getFilmsForCinema('1012');
        await client.getFilmsForCinema('1012');
        await client.getShowingDates('1012');

        expect(server.homepageVisits, 1);
      },
    );

    test(
      'this is the actual regression case: after the token expires (12h - '
      'an app left open in the background for days), the next request '
      're-warms and succeeds. It used to get 401 forever, Retry and '
      'pull-to-refresh included, because the warm-up flag was set once for '
      'the life of the process - only force-closing the app recovered',
      () async {
        final (client, server) = _client();
        await client.getFilmsForCinema('1012');

        server.expireToken();

        await expectLater(client.getFilmsForCinema('1012'), completes);
        await expectLater(client.getShowingDates('1012'), completes);
        expect(server.homepageVisits, 2);
      },
    );

    test('seat maps recover the same way', () async {
      final (client, server) = _client();
      await client.getFilmsForCinema('1012');

      server.expireToken();

      await expectLater(client.getSeatMapJson('1012', 's1'), completes);
    });
    test('a 401 that survives a fresh warm-up is retried once, not in a loop - '
        'then surfaces as the usual friendly error', () async {
      final (client, server) = _client();
      server.rejectEverything = true;

      await expectLater(
        client.getFilmsForCinema('1012'),
        throwsA(isA<ApiException>()),
      );
      expect(server.apiRequests, 2);
      expect(server.homepageVisits, 2);
    });
  });
}
