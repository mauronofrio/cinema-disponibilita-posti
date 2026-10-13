import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thespace_companion/core/catalog/cinema_catalog_repository.dart';
import 'package:thespace_companion/core/date/clock.dart';
import 'package:thespace_companion/features/cinema_picker/cinema_list_provider.dart';

/// No network: every refresh fails, so only the bundled list is in play.
class _Offline implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      throw DioException.connectionError(requestOptions: options, reason: 'offline');

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _entry(String id, {String? minAppVersion}) => {
  'cinemaId': id,
  'name': 'Cinema $id',
  'slug': id,
  'address': 'Via $id',
  'lat': 41.0,
  'lng': 16.0,
  'chain': 'uci',
  'minAppVersion': ?minAppVersion,
};

ProviderContainer _container({
  required List<Map<String, dynamic>> bundled,
  Future<String> Function()? appVersion,
}) {
  final container = ProviderContainer(
    overrides: [
      cinemaCatalogRepositoryProvider.overrideWithValue(
        CinemaCatalogRepository(
          dio: Dio()..httpClientAdapter = _Offline(),
          clock: const Clock(),
          loadBundled: () async => jsonEncode(bundled),
        ),
      ),
      appVersionProvider.overrideWith(
        (ref) => (appVersion ?? () async => '1.0.8')(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('if the app version cannot be read, the bundled list still loads '
      '(as 0.0.0: entries with a minAppVersion are hidden)', () async {
    final container = _container(
      bundled: [_entry('a'), _entry('b', minAppVersion: '1.0.8')],
      appVersion: () async => throw Exception('PackageInfo unavailable'),
    );
    final cinemas = await container.read(cinemaListProvider.future);
    expect(cinemas.map((c) => c.cinemaId), ['a']);
  });

  test('when the active cinema no longer resolves, the first favorite that '
      'does becomes active', () async {
    SharedPreferences.setMockInitialValues({
      'favorite_cinema_ids': ['uci:gone', 'uci:b', 'uci:a'],
      'active_cinema_id': 'uci:gone',
    });
    final container = _container(bundled: [_entry('a'), _entry('b')]);
    final active = await container.read(activeCinemaProvider.future);
    expect(active?.cinemaId, 'b');
  });

  test('with no favorite resolving, there is no active cinema', () async {
    SharedPreferences.setMockInitialValues({
      'favorite_cinema_ids': ['uci:gone'],
      'active_cinema_id': 'uci:gone',
    });
    final container = _container(bundled: [_entry('a')]);
    expect(await container.read(activeCinemaProvider.future), isNull);
  });
}
