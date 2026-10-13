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

/// The app version declared in pubspec.yaml (`version: X.Y.Z+N`), i.e. the
/// version the bundled catalog actually ships with.
String _pubspecVersion() {
  final line = File('pubspec.yaml')
      .readAsLinesSync()
      .firstWhere((l) => l.startsWith('version:'));
  return line.substring('version:'.length).trim().split('+').first;
}

List<String> _ids(String body, {String appVersion = '1.0.8'}) => [
  for (final c in parseCinemaCatalog(body, appVersion: appVersion)) c.cinemaId,
];

void main() {
  test('the real bundled catalog parses completely - no entry is dropped', () {
    final raw = File('assets/cinemas.json').readAsStringSync();
    final all = jsonDecode(raw) as List<dynamic>;
    expect(
      parseCinemaCatalog(raw, appVersion: _pubspecVersion()),
      hasLength(all.length),
    );
  });

  group('an unparseable minAppVersion hides the entry (fail closed)', () {
    for (final bad in <Object>['abc', '1,0,9', 7, '', '1.0.x']) {
      test('minAppVersion ${jsonEncode(bad)} is hidden', () {
        final body = _list([
          _entry(id: 'ok'),
          {..._entry(id: 'bad'), 'minAppVersion': bad},
        ]);
        expect(_ids(body, appVersion: '9.9.9'), ['ok']);
      });
    }

    test('well-formed values still work, build suffix included', () {
      final body = _list([
        _entry(id: 'a', minAppVersion: '1.0.9'),
        _entry(id: 'b', minAppVersion: '1.0.10'),
        _entry(id: 'c', minAppVersion: 'v1.0.9'),
        _entry(id: 'd', minAppVersion: '1.0.9-beta'),
      ]);
      expect(_ids(body, appVersion: '1.0.9+3'), ['a', 'c', 'd']);
    });
  });

  group('per-chain required fields', () {
    test('an 18tickets entry without host is hidden', () {
      final body = _list([
        {..._entry(id: 'ok', chain: 'eighteenTickets'), 'host': 'a.18tickets.it'},
        _entry(id: 'nohost', chain: 'eighteenTickets'),
      ]);
      expect(_ids(body), ['ok']);
    });

    test('a webtic entry without webticLocalId is hidden', () {
      final body = _list([
        {..._entry(id: 'ok', chain: 'webtic'), 'host': 'h', 'webticLocalId': 1},
        {..._entry(id: 'nolid', chain: 'webtic'), 'host': 'h'},
        {
          ..._entry(id: 'portalnolid', chain: 'webtic', source: 'fullSchedulePortal'),
          'host': 'h',
        },
      ]);
      expect(_ids(body), ['ok']);
    });

    test('a webtic entry without host is hidden, except fullSchedulePortal '
        '(it only needs webticLocalId)', () {
      final body = _list([
        for (final source in [
          'fullSchedule',
          'programmingPage',
          'filmSchedulePages',
          'madisonProgrammingPage',
        ])
          {..._entry(id: source, chain: 'webtic', source: source), 'webticLocalId': 1},
        {
          ..._entry(id: 'portal', chain: 'webtic', source: 'fullSchedulePortal'),
          'webticLocalId': 1,
        },
      ]);
      expect(_ids(body), ['portal']);
    });

    test('chains that need neither host nor webticLocalId keep entries '
        'without them', () {
      final body = _list([
        _entry(id: 'space', chain: null),
        _entry(id: 'uci'),
        _entry(id: 'two', chain: 'twoTickets'),
      ]);
      expect(_ids(body), ['space', 'uci', 'two']);
    });
  });

  test('wrong-typed fields hide the entry: chain 5, lat "x"', () {
    final body = _list([
      _entry(id: 'ok'),
      _entry(id: 'chain5', chain: 5),
      {..._entry(id: 'latx'), 'lat': 'x'},
    ]);
    expect(_ids(body), ['ok']);
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
    const required = {'host': 'h', 'webticLocalId': 1};
    final cinemas = parseCinemaCatalog(
      _list([
        {..._entry(id: 'ok', chain: 'webtic', source: 'programmingPage'), ...required},
        {..._entry(id: 'new', chain: 'webtic', source: 'aFutureSource'), ...required},
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
