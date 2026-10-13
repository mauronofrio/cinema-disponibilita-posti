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

  test('every 2Tickets venue uses its id as slug', () {
    for (final c in twoTickets) {
      expect(c.slug, c.cinemaId, reason: c.name);
    }
  });

  test('venues once mis-geocoded sit in their own city', () {
    // Nominatim once returned same-named streets in other towns (Martina
    // Franca, Venosa, Lavello): pin the fixed venues near their cities.
    const near = {
      '1174': (40.47, 17.24), // Taranto
      '7430': (40.64, 15.80), // Potenza
      '2215': (40.64, 15.80), // Potenza
    };
    near.forEach((id, p) {
      final c = twoTickets.firstWhere((c) => c.cinemaId == id);
      expect(c.lat, closeTo(p.$1, 0.1), reason: c.name);
      expect(c.lng, closeTo(p.$2, 0.1), reason: c.name);
    });
  });

  test('Cinema Esperia Padova stays only on 18tickets', () {
    expect(twoTickets.any((c) => c.cinemaId == '1633'), isFalse);
  });

  test('every 18tickets venue has a non-empty host, and no two share one', () {
    final e18 = cinemas.where((c) => c.chain == CinemaChain.eighteenTickets);
    expect(e18.every((c) => (c.host ?? '').isNotEmpty), isTrue);
    final hosts = e18.map((c) => c.host).toList();
    expect(hosts.toSet().length, hosts.length);
  });
}
