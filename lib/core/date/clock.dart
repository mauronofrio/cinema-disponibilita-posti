import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injectable source of "now", so date-boundary logic can be unit tested
/// without touching the device clock.
class Clock {
  const Clock();

  DateTime now() => DateTime.now();
}

final clockProvider = Provider<Clock>((ref) => const Clock());
