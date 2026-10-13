import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/models/cinema.dart';

void main() {
  final cinemas = (json.decode(File('assets/cinemas.json').readAsStringSync())
          as List<dynamic>)
      .map((e) => Cinema.fromJson(e as Map<String, dynamic>))
      .toList();
  final twoTickets =
      cinemas.where((c) => c.chain == CinemaChain.twoTickets).toList();

  test('the catalog includes 2Tickets venues, Conversano among them', () {
    expect(twoTickets, isNotEmpty);
    expect(twoTickets.any((c) => c.cinemaId == '609'), isTrue);
  });

  test('every 2Tickets venue is geocoded inside Italy', () {
    for (final c in twoTickets) {
      expect(c.lat, inInclusiveRange(35.0, 47.5), reason: c.name);
      expect(c.lng, inInclusiveRange(6.0, 19.0), reason: c.name);
    }
  });

  test('no duplicate chain:id keys across the whole catalog', () {
    final keys = cinemas.map((c) => '${c.chain.name}:${c.cinemaId}').toList();
    expect(keys.toSet().length, keys.length);
  });
}
