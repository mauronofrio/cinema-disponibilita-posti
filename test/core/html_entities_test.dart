import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/util/html_entities.dart';

void main() {
  group('decodeHtmlEntities', () {
    test('hex, decimal and named entities', () {
      expect(decodeHtmlEntities('L&#x27;&#x27;ESTRANEA'), "L''ESTRANEA");
      expect(decodeHtmlEntities("c&#39;&egrave;"), "c'è");
      expect(decodeHtmlEntities('A &amp; B'), 'A & B');
    });

    test('unknown entities are left untouched', () {
      expect(decodeHtmlEntities('&bogus;'), '&bogus;');
    });

    test('out-of-range code points are left untouched, never throw', () {
      expect(decodeHtmlEntities('&#99999999;'), '&#99999999;');
      expect(decodeHtmlEntities('&#xFFFFFFFF;'), '&#xFFFFFFFF;');
    });
  });
}
