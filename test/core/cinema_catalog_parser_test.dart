import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/catalog/cinema_catalog_parser.dart';
import 'package:thespace_companion/core/models/cinema.dart';

Map<String, dynamic> _entry({
  String id = 'x',
  Object? chain = 'uci',
  Object? source,
  String? minAppVersion,
}) => {
  'cinemaId': id,
  'name': 'Cinema $id',
  'slug': id,
  'address': 'Via X 1',
  'lat': 41.0,
  'lng': 16.0,
  'chain': chain,
  'webticCatalogSource': ?source,
  'minAppVersion': ?minAppVersion,
};

String _list(List<Map<String, dynamic>> entries) => jsonEncode(entries);

void main() {
  test('the real bundled catalog parses completely - no entry is dropped', () {
    final raw = File('assets/cinemas.json').readAsStringSync();
    final all = jsonDecode(raw) as List<dynamic>;
    expect(parseCinemaCatalog(raw, appVersion: '1.0.7'), hasLength(all.length));
  });

  test('this is the actual regression case: an unknown chain is hidden, '
      'never routed to The Space as CinemaChain.fromJson used to do', () {
    final cinemas = parseCinemaCatalog(
      _list([_entry(id: 'a'), _entry(id: 'b', chain: 'aFutureChain')]),
      appVersion: '1.0.8',
    );
    expect(cinemas.map((c) => c.cinemaId), ['a']);
  });

  test('a missing chain still means The Space (legacy entries)', () {
    final c = parseCinemaCatalog(
      _list([_entry(chain: null)]),
      appVersion: '1.0.8',
    ).single;
    expect(c.chain, CinemaChain.theSpace);
  });

  test('an unknown Webtic catalog source is hidden, not guessed', () {
    final cinemas = parseCinemaCatalog(
      _list([
        _entry(id: 'ok', chain: 'webtic', source: 'programmingPage'),
        _entry(id: 'new', chain: 'webtic', source: 'aFutureSource'),
      ]),
      appVersion: '1.0.8',
    );
    expect(cinemas.map((c) => c.cinemaId), ['ok']);
  });

  test('minAppVersion hides an entry from older apps only', () {
    final body = _list([_entry(id: 'n', minAppVersion: '1.0.9')]);
    expect(parseCinemaCatalog(body, appVersion: '1.0.8'), isEmpty);
    expect(parseCinemaCatalog(body, appVersion: '1.0.9'), hasLength(1));
    expect(parseCinemaCatalog(body, appVersion: '1.1.0'), hasLength(1));
  });

  test('a malformed entry is skipped, the rest survive', () {
    final cinemas = parseCinemaCatalog(
      jsonEncode([
        _entry(id: 'good'),
        {'cinemaId': 'bad', 'name': 'No coordinates'},
        'not even a map',
      ]),
      appVersion: '1.0.8',
    );
    expect(cinemas.map((c) => c.cinemaId), ['good']);
  });

  test('a body that is not a JSON list is a FormatException', () {
    expect(
      () => parseCinemaCatalog('{"oops": true}', appVersion: '1.0.8'),
      throwsFormatException,
    );
    expect(
      () => parseCinemaCatalog('<html>', appVersion: '1.0.8'),
      throwsFormatException,
    );
  });
}
