import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Must produce exactly what tools/update_readme_counts.py writes.
String expectedBlock() {
  final entries = jsonDecode(File('assets/cinemas.json').readAsStringSync())
      as List<dynamic>;
  final counts = <String, int>{};
  for (final e in entries.cast<Map<String, dynamic>>()) {
    final chain = (e['chain'] as String?) ?? 'theSpace';
    counts[chain] = (counts[chain] ?? 0) + 1;
  }
  int n(String k) => counts[k] ?? 0;
  return '<!-- cinema-counts:start -->\n'
      '**${entries.length} cinema supportati** · The Space ${n('theSpace')} · '
      'UCI ${n('uci')} · 18tickets ${n('eighteenTickets')} · '
      'Webtic ${n('webtic')} · 2Tickets ${n('twoTickets')}\n'
      '<!-- cinema-counts:end -->';
}

void main() {
  test('README cinema counts match assets/cinemas.json - if this fails, run '
      'python tools/update_readme_counts.py', () {
    final readme = File('README.md').readAsStringSync().replaceAll('\r\n', '\n');
    expect(readme, contains(expectedBlock()));
  });
}
