import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2Tickets serves the cinemas' payment-gateway credentials in public
/// responses (their bug). Fixtures were sanitized by hand when captured -
/// this keeps a future fixture refresh from silently committing them.
///
/// `tipoBanca` is only a numeric gateway-type code (`tipoBanca: 1`), not a
/// secret, so it is not checked; `CONFIG.userBanca`-style references in the
/// page's JS are code, not values.
void main() {
  test('no 2Tickets fixture carries real payment credentials', () {
    final leak = RegExp(
      r'''(userBanca|pwdBanca)"?\s*:\s*["']?(?!REDACTED|CONFIG\.)[A-Za-z0-9_]''',
    );
    final offenders = Directory('test/fixtures')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.split(Platform.pathSeparator).last.startsWith('twotickets_'))
        .where((f) => leak.hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty);
  });
}
