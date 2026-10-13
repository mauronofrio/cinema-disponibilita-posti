/// One showtime from a 2Tickets checkout page's embedded `orariServer` list.
class TwoTicketsPerformance {
  const TwoTicketsPerformance({
    required this.eventId,
    required this.startTime,
    required this.rawTime,
    required this.hall,
    required this.freeSeats,
    required this.is3D,
    required this.isOriginalLanguage,
    required this.isAtmos,
  });

  final String eventId;
  final DateTime startTime;

  /// The time exactly as sent ("21.30") - the booking link and the seats
  /// call both want it in this form.
  final String rawTime;
  final String hall;

  /// `postiLiberi`. 9999 is the site's own "not tracked" sentinel (its JS
  /// treats it as plenty available), so only 0 means sold out.
  final int freeSeats;
  final bool is3D;
  final bool isOriginalLanguage;
  final bool isAtmos;

  bool get isSoldOut => freeSeats == 0;
}

class TwoTicketsCheckoutPage {
  const TwoTicketsCheckoutPage({
    required this.serverEse,
    required this.portEse,
    required this.performances,
  });

  final String serverEse;
  final String portEse;
  final List<TwoTicketsPerformance> performances;
}

final _push = RegExp(r'orariServer\.push\(\{(.*?)\}\);', dotAll: true);
final _serverEse = RegExp(r'serverEse:\s*"([^"]*)"');
final _portEse = RegExp(r'portEse:\s*"([^"]*)"');

String? _field(String block, String name) => RegExp(
  '\\b$name:\\s*["\']?([^,"\'\\n]*)',
).firstMatch(block)?.group(1)?.trim();

/// Parses `/biglietto/Acquisto/Checkout/{idFilm}/{idLocale}?settore=C`.
///
/// The page embeds **every** on-sale date for this film at this venue (the
/// site's calendar is built client-side from it - confirmed: switching date
/// makes no request), so one page per film is the whole schedule. Only the
/// handful of fields below are read; in particular the page config's
/// payment-gateway credentials (exposed by the site, not ours to touch) are
/// never looked at.
TwoTicketsCheckoutPage parseTwoTicketsCheckoutPage(String html) {
  final performances = <TwoTicketsPerformance>[];
  for (final match in _push.allMatches(html)) {
    final block = match.group(1)!;
    final id = _field(block, 'idEvento');
    final date = _field(block, 'data');
    final time = _field(block, 'ora');
    if (id == null || date == null || time == null) continue;
    final day = DateTime.tryParse(date);
    final hm = time.split('.');
    final hour = int.tryParse(hm.first);
    final minute = hm.length > 1 ? int.tryParse(hm[1]) : 0;
    if (day == null || hour == null || minute == null) continue;
    performances.add(
      TwoTicketsPerformance(
        eventId: id,
        startTime: DateTime(day.year, day.month, day.day, hour, minute),
        rawTime: time,
        hall: _field(block, 'sala') ?? '',
        freeSeats: int.tryParse(_field(block, 'postiLiberi') ?? '') ?? 9999,
        is3D: _field(block, 'is3D') == 'true',
        isOriginalLanguage: _field(block, 'isVO') == 'true',
        isAtmos: _field(block, 'isAtmos') == 'true',
      ),
    );
  }
  return TwoTicketsCheckoutPage(
    serverEse: _serverEse.firstMatch(html)?.group(1) ?? '',
    portEse: _portEse.firstMatch(html)?.group(1) ?? '',
    performances: performances,
  );
}
