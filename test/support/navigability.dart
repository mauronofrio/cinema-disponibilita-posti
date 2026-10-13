import 'package:thespace_companion/core/chains/chain_api.dart';
import 'package:thespace_companion/core/models/cinema.dart';
import 'package:thespace_companion/core/models/film.dart';

enum Navigability { navigable, programmeOnly, notNavigable, notVerifiableNow }

class NavigabilityResult {
  const NavigabilityResult(this.cinema, this.verdict, this.reason);
  final Cinema cinema;
  final Navigability verdict;
  final String reason;

  Map<String, dynamic> toJson() => {
    'chain': cinema.chain.name,
    'cinemaId': cinema.cinemaId,
    'name': cinema.name,
    'verdict': verdict.name,
    'reason': reason,
  };
}

/// Whether [cinema] works end to end in the app, judged by the app's own
/// [ChainApi] on live data: programme within 7 days, a future session whose
/// seat map has seats (or an unnumbered sector), and a booking link. A
/// cinema with nothing scheduled right now can't be judged either way.
///
/// A failed request is retried once after [retryDelay] (via [pause], injectable
/// so tests don't sleep): a transient error or an HTTP 429 must not decide the
/// verdict. A failing seat map is also tried on the second future session.
Future<NavigabilityResult> checkNavigability(
  ChainApi api,
  Cinema cinema,
  DateTime now, {
  Future<void> Function(Duration) pause = _sleep,
  Duration retryDelay = const Duration(seconds: 10),
}) async {
  Future<T> retried<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (_) {
      await pause(retryDelay);
      return call();
    }
  }

  NavigabilityResult r(Navigability v, String why) =>
      NavigabilityResult(cinema, v, why);
  final today = DateTime(now.year, now.month, now.day);
  final horizon = DateTime(now.year, now.month, now.day + 7);

  final List<DateTime> days;
  try {
    days = [
      for (final d in await retried(() => api.getShowingDates(cinema)))
        if (d.hasShowings && !d.date.isBefore(today) && d.date.isBefore(horizon))
          DateTime(d.date.year, d.date.month, d.date.day),
    ];
  } catch (e) {
    return r(Navigability.notNavigable, 'programmazione: $e');
  }
  if (days.isEmpty) {
    return r(Navigability.notVerifiableNow, 'nessuna programmazione nei prossimi 7 giorni');
  }

  final future = <Session>[];
  try {
    for (final day in days) {
      for (final film in await retried(() => api.getFilmsForDay(cinema, day))) {
        future.addAll(film.sessionsOn(day).where((s) => s.startTime.isAfter(now)));
      }
      if (future.isNotEmpty) break;
    }
  } catch (e) {
    return r(Navigability.notNavigable, 'film: $e');
  }
  if (future.isEmpty) {
    return r(Navigability.notVerifiableNow, 'nessuno spettacolo futuro nei prossimi 7 giorni');
  }
  future.sort((a, b) => a.startTime.compareTo(b.startTime));

  if (!cinema.hasSeatMap) {
    return r(Navigability.programmeOnly, 'cinema senza mappa posti per scelta');
  }
  Session? session;
  String? seatError;
  final candidates = future.take(2).toList();
  for (var i = 0; i < candidates.length && session == null; i++) {
    final candidate = candidates[i];
    // Retry the first session once; the second one gets a single attempt.
    for (var attempt = 0; attempt < (i == 0 ? 2 : 1); attempt++) {
      if (attempt > 0) await pause(retryDelay);
      try {
        final map = await api.getSeatMap(cinema, candidate);
        if (map.rows.isEmpty && map.unnumberedSectors.isEmpty) {
          return r(Navigability.programmeOnly, 'mappa posti vuota');
        }
        session = candidate;
        break;
      } catch (e) {
        seatError = '$e';
      }
    }
  }
  if (session == null) {
    return r(Navigability.programmeOnly, 'mappa posti: $seatError');
  }
  if (session.bookingPath == null) {
    return r(Navigability.programmeOnly, 'manca il link di acquisto');
  }
  return r(Navigability.navigable, 'ok');
}

Future<void> _sleep(Duration d) => Future<void>.delayed(d);
