import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thespace_companion/core/catalog/cinema_catalog_repository.dart';
import 'package:thespace_companion/core/date/clock.dart';

class _Clock extends Clock {
  _Clock(this.value);
  DateTime value;
  @override
  DateTime now() => value;
}

/// Plays GitHub raw: serves [body] with an ETag, answers 304 to a matching
/// If-None-Match, or fails/returns garbage when told to.
class _FakeGitHub implements HttpClientAdapter {
  String body = _catalog(4);
  String etag = '"v1"';
  int status = 200;
  bool fail = false;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    if (fail) throw DioException.connectionError(requestOptions: options, reason: 'offline');
    if (options.headers['If-None-Match'] == etag) {
      return ResponseBody.fromString('', 304);
    }
    return ResponseBody.fromString(body, status, headers: {
      'etag': [etag],
      'content-type': ['text/plain; charset=utf-8'],
    });
  }

  @override
  void close({bool force = false}) {}
}

String _catalog(int n) => jsonEncode([
  for (var i = 0; i < n; i++)
    {
      'cinemaId': 'c$i',
      'name': 'Cinema $i',
      'slug': 'c$i',
      'address': 'Via $i',
      'lat': 41.0,
      'lng': 16.0,
      'chain': 'uci',
    },
]);

void main() {
  late _FakeGitHub github;
  late _Clock clock;
  late CinemaCatalogRepository repo;

  CinemaCatalogRepository build() => CinemaCatalogRepository(
    dio: Dio()..httpClientAdapter = github,
    clock: clock,
    loadBundled: () async => _catalog(4),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    github = _FakeGitHub();
    clock = _Clock(DateTime(2026, 10, 20, 9));
    repo = build();
  });

  test('first run with no cache: bundled list', () async {
    expect(await repo.load(appVersion: '1.0.8'), hasLength(4));
  });

  test('a successful refresh is used from then on', () async {
    github.body = _catalog(5);
    expect(await repo.refreshIfStale(appVersion: '1.0.8'), isTrue);
    expect(await build().load(appVersion: '1.0.8'), hasLength(5));
  });

  test('at most one check per 24h, and a 304 changes nothing', () async {
    github.body = _catalog(5);
    await repo.refreshIfStale(appVersion: '1.0.8');
    expect(await repo.refreshIfStale(appVersion: '1.0.8'), isFalse);
    expect(github.requests, 1);
    clock.value = clock.value.add(const Duration(hours: 25));
    expect(await repo.refreshIfStale(appVersion: '1.0.8'), isFalse); // 304
    expect(github.requests, 2);
    expect(await repo.load(appVersion: '1.0.8'), hasLength(5));
  });

  test('Review Focus 1: offline or a 5xx keeps the last good list and '
      'retries on the next launch', () async {
    github.body = _catalog(5);
    await repo.refreshIfStale(appVersion: '1.0.8');
    clock.value = clock.value.add(const Duration(hours: 25));
    github.fail = true;
    expect(await repo.refreshIfStale(appVersion: '1.0.8'), isFalse);
    expect(await repo.load(appVersion: '1.0.8'), hasLength(5));
    github
      ..fail = false
      ..status = 503
      ..etag = '"v2"';
    expect(await repo.refreshIfStale(appVersion: '1.0.8'), isFalse);
    expect(await repo.load(appVersion: '1.0.8'), hasLength(5));
  });

  test('Review Focus 3: a truncated / mostly-empty list is rejected', () async {
    github.body = _catalog(1); // bundled has 4 -> below half
    expect(await repo.refreshIfStale(appVersion: '1.0.8'), isFalse);
    expect(await repo.load(appVersion: '1.0.8'), hasLength(4));
    github
      ..body = '<html>Not Found</html>'
      ..etag = '"v3"';
    clock.value = clock.value.add(const Duration(hours: 25));
    expect(await repo.refreshIfStale(appVersion: '1.0.8'), isFalse);
    expect(await repo.load(appVersion: '1.0.8'), hasLength(4));
  });

  test('a list with duplicate chain:cinemaId keys is rejected', () async {
    final dup = jsonDecode(_catalog(4)) as List<dynamic>
      ..add((jsonDecode(_catalog(1)) as List<dynamic>).first);
    github.body = jsonEncode(dup);
    expect(await repo.refreshIfStale(appVersion: '1.0.8'), isFalse);
  });

  test('a cache written by an older app version is discarded on upgrade', () async {
    github.body = _catalog(5);
    await repo.refreshIfStale(appVersion: '1.0.8');
    expect(await build().load(appVersion: '1.0.9'), hasLength(4));
  });

  test('a failure inside refresh (unparseable bundled list) is just false', () async {
    final broken = CinemaCatalogRepository(
      dio: Dio()..httpClientAdapter = github,
      clock: clock,
      loadBundled: () async => throw StateError('asset missing'),
    );
    expect(await broken.refreshIfStale(appVersion: '1.0.8'), isFalse);
  });
}
