@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/catalog/cinema_catalog_parser.dart';
import 'package:thespace_companion/core/chains/chain_registry.dart';

import '../support/navigability.dart';

const _file = String.fromEnvironment('VERIFY_FILE', defaultValue: 'assets/cinemas.json');
const _chain = String.fromEnvironment('VERIFY_CHAIN');
const _ids = String.fromEnvironment('VERIFY_IDS');
const _delayMs = int.fromEnvironment('VERIFY_DELAY_MS', defaultValue: 4000);
const _report = String.fromEnvironment('VERIFY_REPORT', defaultValue: 'build/navigability_report.json');

void main() {
  test('navigability of the selected cinemas (live)', () async {
    // Version high enough that minAppVersion never hides a candidate here.
    var cinemas = parseCinemaCatalog(File(_file).readAsStringSync(), appVersion: '999.0.0');
    if (_chain.isNotEmpty) cinemas = cinemas.where((c) => c.chain.name == _chain).toList();
    if (_ids.isNotEmpty) {
      final ids = _ids.split(',').map((s) => s.trim()).toSet();
      cinemas = cinemas.where((c) => ids.contains(c.cinemaId)).toList();
    }
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final results = <NavigabilityResult>[];
    for (final c in cinemas) {
      final api = container.read(chainApiProvider(c.chain));
      final r = await checkNavigability(api, c, DateTime.now());
      results.add(r);
      // ignore: avoid_print
      print('${switch (r.verdict) {
        Navigability.navigable => 'OK  ',
        Navigability.programmeOnly => 'PROG',
        Navigability.notNavigable => 'KO  ',
        Navigability.notVerifiableNow => 'WAIT',
      }} ${c.chain.name}:${c.cinemaId} ${c.name} - ${r.reason}');
      await Future<void>.delayed(const Duration(milliseconds: _delayMs));
    }
    File(_report)
      ..createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ')
          .convert([for (final r in results) r.toJson()]));
  }, timeout: const Timeout(Duration(hours: 2)));
}
