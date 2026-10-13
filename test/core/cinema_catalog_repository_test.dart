import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thespace_companion/core/catalog/cinema_catalog_repository.dart';
import 'package:thespace_companion/core/date/clock.dart';
import 'package:thespace_companion/core/models/cinema.dart';

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

  /// Headers of the last request received.
  Map<String, dynamic> lastHeaders = {};

  /// When set, every response waits for it - to keep a request in flight.
  Completer<void>? hold;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    lastHeaders = Map.of(options.headers);
    if (hold != null) await hold!.future;
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

Map<String, dynamic> _entry(int i) => {
  'cinemaId': 'c$i',
  'name': 'Cinema $i',
  'slug': 'c$i',
  'address': 'Via $i',
  'lat': 41.0,
  'lng': 16.0,
  'chain': 'uci',
};

String _catalog(int n) => jsonEncode([for (var i = 0; i < n; i++) _entry(i)]);

List<String> _ids(List<Cinema> cinemas) =>
    [for (final c in cinemas) c.cinemaId]..sort();

String _withEntries(List<Map<String, dynamic>> entries) => jsonEncode(entries);

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

  group('a bundled cinema is never lost to the remote list', () {
    test('a remote list missing two bundled cinemas still shows them', () async {
      github.body = _withEntries([_entry(0), _entry(1)]);
      await repo.refreshIfStale(appVersion: '1.0.8');
      expect(
        _ids(await build().load(appVersion: '1.0.8')),
        ['c0', 'c1', 'c2', 'c3'],
      );
    });

    test('a bundled key kept remotely with minAppVersion "99" is hidden '
        '(remote wins for keys it contains)', () async {
      github.body = _withEntries([
        _entry(0),
        _entry(1),
        _entry(2),
        {..._entry(3), 'minAppVersion': '99'},
      ]);
      await repo.refreshIfStale(appVersion: '1.0.8');
      expect(_ids(await build().load(appVersion: '1.0.8')), ['c0', 'c1', 'c2']);
    });

    test('a new remote cinema shows alongside the bundled ones', () async {
      github.body = _withEntries([_entry(0), _entry(9)]);
      await repo.refreshIfStale(appVersion: '1.0.8');
      expect(
        _ids(await build().load(appVersion: '1.0.8')),
        ['c0', 'c1', 'c2', 'c3', 'c9'],
      );
    });

    test('a bundled key present remotely with a malformed field is hidden: '
        'the key is in the raw remote list, so the remote wins', () async {
      github.body = _withEntries([
        _entry(0),
        _entry(1),
        _entry(2),
        {..._entry(3), 'lat': 'x'},
      ]);
      await repo.refreshIfStale(appVersion: '1.0.8');
      expect(_ids(await build().load(appVersion: '1.0.8')), ['c0', 'c1', 'c2']);
    });
  });

  test('a clock moved backwards makes the last check stale', () async {
    await repo.refreshIfStale(appVersion: '1.0.8');
    clock.value = clock.value.subtract(const Duration(hours: 1));
    await repo.refreshIfStale(appVersion: '1.0.8');
    expect(github.requests, 2);
  });

  for (final status in [404, 429]) {
    test('a $status counts as a completed check: one request per 24h', () async {
      github.status = status;
      expect(await repo.refreshIfStale(appVersion: '1.0.8'), isFalse);
      await build().refreshIfStale(appVersion: '1.0.8');
      expect(github.requests, 1);
      clock.value = clock.value.add(const Duration(hours: 25));
      await build().refreshIfStale(appVersion: '1.0.8');
      expect(github.requests, 2);
      expect(await repo.load(appVersion: '1.0.8'), hasLength(4));
    });
  }

  test('a 503 is retried on the next launch', () async {
    github.status = 503;
    await repo.refreshIfStale(appVersion: '1.0.8');
    await build().refreshIfStale(appVersion: '1.0.8');
    expect(github.requests, 2);
  });

  test('concurrent refreshes share one request', () async {
    github.hold = Completer<void>();
    final a = repo.refreshIfStale(appVersion: '1.0.8');
    final b = repo.refreshIfStale(appVersion: '1.0.8');
    // Let both calls run as far as they can while the response is held.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    github.hold!.complete();
    await Future.wait([a, b]);
    expect(github.requests, 1);
  });

  test('after an offline launch, the next launch makes a new request', () async {
    github.fail = true;
    await repo.refreshIfStale(appVersion: '1.0.8');
    github.fail = false;
    await build().refreshIfStale(appVersion: '1.0.8');
    expect(github.requests, 2);
  });

  test('the first refresh after an app upgrade ignores the 24h gate', () async {
    await repo.refreshIfStale(appVersion: '1.0.8');
    await build().refreshIfStale(appVersion: '1.0.9');
    expect(github.requests, 2);
  });

  test('no If-None-Match is sent when no ETag is stored', () async {
    await repo.refreshIfStale(appVersion: '1.0.8');
    expect(github.lastHeaders.containsKey('If-None-Match'), isFalse);
    clock.value = clock.value.add(const Duration(hours: 25));
    await repo.refreshIfStale(appVersion: '1.0.8');
    expect(github.lastHeaders['If-None-Match'], '"v1"');
  });
}
