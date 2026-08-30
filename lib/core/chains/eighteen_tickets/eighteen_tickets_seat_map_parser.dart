import 'dart:convert';

import '../../models/seat_map.dart';

/// Bundles both raw responses into one argument so parsing can still happen
/// in a single `compute()` call if the SVG turns out large enough to
/// warrant it (same reasoning as the other two chains' seat map payloads).
class EighteenTicketsSeatMapPayload {
  const EighteenTicketsSeatMapPayload({
    required this.theaterSvg,
    required this.occupancyJson,
  });

  final String theaterSvg;
  final String occupancyJson;
}

class _RawSeat {
  const _RawSeat({
    required this.seatId,
    required this.row,
    required this.seatNumber,
    required this.area,
    required this.x,
    required this.y,
    required this.isAccessibility,
    required this.isNotForSale,
  });

  final String seatId;
  final String row;
  final String seatNumber;
  final String area;
  final double x;

  /// Only used to sort rows by real distance from the screen (see
  /// [_screenYRe]) - never for column placement, that's [x].
  final double y;

  /// Accessibility/wheelchair seats carry an extra `special userhide` class
  /// alongside `posto`, with an empty `data-note` (confirmed live: always
  /// the two seats at either end of the row farthest from the screen) - not
  /// offered through the normal booking flow at all ("userhide"). The old
  /// class match required the attribute to be *exactly* `posto`, which
  /// silently dropped every one of these seats from the parsed room
  /// entirely (a gap in the grid, not just a wrong color) since their real
  /// class value never matched.
  final bool isAccessibility;

  /// True for a seat carrying that same `special userhide` class but a
  /// *non-empty* `data-note` - confirmed live on Multisala Massimo - Lecce's
  /// largest room: 253 of its 701 seats carry it, tagged
  /// `data-note='Galleria'`, an entire upper-gallery section reused this
  /// same "hidden from booking" class for, not individual accessibility
  /// seats. Left out of the parsed room entirely (see
  /// [parseEighteenTicketsSeatMap]) rather than rendered with any status at
  /// all - these were never real bookable seats to begin with, and a
  /// seat-shaped placeholder there reads as "taken", not "not really part
  /// of this room".
  final bool isNotForSale;
}

final _seatGroupRe = RegExp(
  r"""<g class=['"]([^'"]*)['"][^>]*data-area=['"]([^'"]*)['"][^>]*data-row=['"]([^'"]*)['"][^>]*data-seat=['"]([^'"]*)['"][^>]*>\s*<rect[^>]*id=['"]([^'"]+)['"][^>]*x=['"]([\d.]+)['"][^>]*y=['"]([\d.]+)['"]""",
);

/// [_seatGroupRe] doesn't capture this itself (adding a group would shift
/// every existing group index) - looked up separately, only to tell a real
/// accessibility seat's `special userhide` class apart from Multisala
/// Massimo - Lecce's *reuse* of that exact same class for its whole
/// upper-gallery section (confirmed live: 253 of that one room's 701 seats
/// carry it, spanning nearly every row - far too many and far too
/// spread-out to be individual companion seats - each one tagged
/// `data-note='Galleria'`, unlike a real accessibility seat's always-empty
/// `data-note`). Without this check, that entire gallery section would
/// render - and count - as accessibility seating.
final _noteRe = RegExp(r"""data-note=['"]([^'"]*)['"]""");

/// The room's own screen indicator - always present as a `<rect
/// class='m18-th-screen' .../>`, its `y` is the one fixed point every row's
/// distance is measured from (see the row-order comment on
/// [parseEighteenTicketsSeatMap] for why this replaced trusting the row
/// label itself).
final _screenYRe = RegExp(
  r"""class=['"]m18-th-screen['"][^>]*y=['"]([\d.]+)['"]""",
);

/// Categories the occupancy JSON's own arrays use (see PROJECT_NOTES.md) -
/// every seat id in any of these is unavailable; a seat id absent from all
/// of them is free. `mine`/`preemption` are only meaningful for a logged-in
/// booking session this app never has, but are still treated as
/// unavailable rather than assumed free if they ever show up.
const _busyKeys = [
  'bought',
  'locked',
  'reserved',
  'quarantined',
  'reselling',
  'mine',
  'preemption',
];

/// Every busy-category array holds either a plain seat-id string (confirmed
/// on RedCarpet, e.g. `"11_7"`) or an object `{"sid": 31706, "x": 6, "y": 10}`
/// (confirmed on Multicinema Galleria, on a real reserved seat) - `sid` is
/// some other internal id not seen anywhere else, but `x`/`y` are the same
/// two numbers that make up the SVG `<rect>`'s own `id` (`"${y}_${x}"`, row
/// grid index first) - reconstructing it that way matches a real seat
/// (verified live: `{"x": 6, "y": 10}` for a session with row A seats 3/4/5
/// reserved matched rect ids "10_6"/"10_7"/"10_8", the same seats). Without
/// this, `.toString()`-ing the object produced a garbage string that could
/// never match any real seat id, so every seat silently read as available
/// regardless of true occupancy.
String _busySeatId(dynamic entry) {
  if (entry is Map) return '${entry['y']}_${entry['x']}';
  return entry.toString();
}

/// `reserved` gets its own [SeatStatus] (this platform's own legend calls it
/// "Prenotati in cassa", counter-booked rather than fully sold) - everything
/// else busy collapses to plain `occupied`, same simplification The Space's
/// own status codes already make for several distinct server states.
///
/// [isAccessibility] only affects the *free* case: the grid's own color/icon
/// treatment for accessibility seats (see seat_grid.dart) keys off
/// `status == SeatStatus.accessibility` specifically, not the separate
/// `Seat.isAccessibility` flag (that one only drives the occupancy-count
/// exclusion) - so an unbooked accessibility seat needs this status
/// explicitly, not just `available`. A *busy* accessibility seat still
/// reads as occupied/reserved like any other seat - there's no visual way
/// to tell "this occupied seat happened to be accessibility" apart from a
/// regular one, only that it doesn't count towards the totals.
SeatStatus _statusFor(
  String seatId,
  Map<String, Set<String>> busyBySeatId,
  bool isAccessibility,
) {
  if (busyBySeatId['reserved']!.contains(seatId)) return SeatStatus.reserved;
  for (final key in _busyKeys) {
    if (busyBySeatId[key]!.contains(seatId)) return SeatStatus.occupied;
  }
  return isAccessibility ? SeatStatus.accessibility : SeatStatus.available;
}

/// Parses a `theater/{id}.svg` layout together with a `seats/{id}`
/// occupancy response into the same [SeatMap] shape the UI already renders
/// for the other two chains.
///
/// The SVG gives each seat's exact x/y position rather than discrete
/// row/column numbers - column order is derived from real x position rather
/// than trusting `data-seat` (observed to *decrease* left-to-right in at
/// least one real room, so it's only ever used for the visible label, never
/// for placement).
///
/// Row order is by real distance from the room's own screen indicator
/// (closest first), not the row label. A label-based rule ("A is always the
/// back row") was tried first and briefly shipped, on the strength of a
/// Multicinema Galleria "Backrooms" room whose SVG *geometry* put row "A"
/// nearest the screen while the room's real layout has it at the back - but
/// that turned out to be the user misremembering that one room, not a
/// platform quirk (confirmed live once checked against the actual booking
/// page). Multisala Massimo - Lecce then surfaced a real room built the
/// opposite way on purpose (screen at the *bottom* of its SVG, row "A"
/// genuinely closest) - proof "A is always the back row" was never true
/// platform-wide. Measuring real distance from each room's own screen
/// element gets both right without hardcoding either one, because it's
/// just reading what that room's own SVG actually draws. A "DD" row label,
/// seen in a couple of rooms, isn't a real row at all (confirmed by the
/// user) - just a companion/accessible seat sitting on the same physical
/// line as row A - so it's merged into "A" before any of this rather than
/// kept as its own phantom row.
SeatMap parseEighteenTicketsSeatMap(EighteenTicketsSeatMapPayload payload) {
  final rawSeats = <_RawSeat>[];
  for (final match in _seatGroupRe.allMatches(payload.theaterSvg)) {
    final classAttr = match.group(1)!;
    final note = _noteRe.firstMatch(match.group(0)!)?.group(1) ?? '';
    final hasSpecialClass =
        classAttr.contains('special') || classAttr.contains('userhide');
    rawSeats.add(
      _RawSeat(
        area: match.group(2)!,
        row: match.group(3)!,
        seatNumber: match.group(4)!,
        seatId: match.group(5)!,
        x: double.parse(match.group(6)!),
        y: double.parse(match.group(7)!),
        isAccessibility: hasSpecialClass && note.isEmpty,
        isNotForSale: hasSpecialClass && note.isNotEmpty,
      ),
    );
  }
  final screenY = double.parse(
    _screenYRe.firstMatch(payload.theaterSvg)!.group(1)!,
  );

  final occupancy = json.decode(payload.occupancyJson) as Map<String, dynamic>;
  final busyBySeatId = <String, Set<String>>{
    for (final key in _busyKeys)
      key: ((occupancy[key] as List<dynamic>?) ?? const [])
          .map(_busySeatId)
          .toSet(),
  };

  final distinctX = rawSeats.map((s) => s.x).toSet().toList()..sort();
  final columnForX = {
    for (var i = 0; i < distinctX.length; i++) distinctX[i]: i + 1,
  };
  final totalColumns = distinctX.length;

  // Not-for-sale seats (see _RawSeat.isNotForSale) are dropped before
  // grouping into rows, not just before rendering. Multisala Massimo -
  // Lecce's upper gallery reuses the exact same row *letters* as the
  // stalls below it - grouping first and filtering afterwards let every
  // shared letter's [distanceFromScreen] average in the gallery seats'
  // `y`, dragging the sort key toward the gallery and scrambling the whole
  // room's front-to-back order (confirmed live: rendered as
  // "A, B, O, P, Q, M, R, N, C, S, D, T, F, G, L, H, E, I, U" instead of
  // "A...U"). Filtering first means each row's average `y` - and therefore
  // its distance from the screen - only ever reflects that row's own real,
  // bookable seats.
  final saleableSeats = rawSeats.where((s) => !s.isNotForSale).toList();

  final byRow = <String, List<_RawSeat>>{};
  for (final seat in saleableSeats) {
    // "DD" isn't a real row of its own (confirmed by the user) - every
    // example seen is a single companion/accessible seat sitting right next
    // to row A on the exact same physical line, just labelled separately in
    // the raw data. Merged into "A" here so it renders as part of that row
    // instead of as its own phantom row.
    final rowKey = seat.row == 'DD' ? 'A' : seat.row;
    byRow.putIfAbsent(rowKey, () => []).add(seat);
  }
  final distanceFromScreen = {
    for (final entry in byRow.entries)
      entry.key:
          (entry.value.map((s) => s.y).reduce((a, b) => a + b) /
                      entry.value.length -
                  screenY)
              .abs(),
  };
  final rowLabels = byRow.keys.toList()
    ..sort((a, b) => distanceFromScreen[a]!.compareTo(distanceFromScreen[b]!));

  final rows = rowLabels.map((rowLabel) {
    final rowIndex = rowLabel.isEmpty ? 0 : rowLabel.codeUnitAt(0);
    final slots = List<Seat?>.filled(totalColumns, null);
    // Every seat already had isNotForSale ones removed above, when rows
    // were grouped - nothing left to filter out here.
    final seatsInRow = byRow[rowLabel]!;
    // The merged-in "DD" seat always carries its own raw seat number "1",
    // which can collide with a real seat already numbered "1" in the row it
    // merges into - detected here (rather than assumed only for merges) so
    // any other room with a genuine duplicate is covered too. When that
    // happens, the whole row falls back to a left-to-right position number
    // instead of the raw (colliding) one.
    final numbersCollide =
        seatsInRow.map((s) => s.seatNumber).toSet().length < seatsInRow.length;
    final byX = [...seatsInRow]..sort((a, b) => a.x.compareTo(b.x));
    final positionForSeat = {
      for (var i = 0; i < byX.length; i++) byX[i]: i + 1,
    };
    for (final raw in seatsInRow) {
      final column = columnForX[raw.x]!;
      final label = numbersCollide ? '${positionForSeat[raw]}' : raw.seatNumber;
      slots[column - 1] = Seat(
        rowIndex: rowIndex,
        columnIndex: column,
        name: '$rowLabel$label',
        status: _statusFor(raw.seatId, busyBySeatId, raw.isAccessibility),
        areaCategoryCode: raw.area,
        isAccessibility: raw.isAccessibility,
      );
    }
    return SeatRow(rowLabel: rowLabel, rowIndex: rowIndex, seats: slots);
  }).toList();

  // No per-category color/name is available anywhere in what this platform
  // exposes (the SVG's own seat fill is a generic placeholder gray, not a
  // real pricing-category color) - every available seat falls back to the
  // shared uniform "available" color instead of one per category.
  return SeatMap(
    screenLabel: '',
    totalRows: rows.length,
    totalColumns: totalColumns,
    rows: rows,
    areaCategories: const [],
  );
}
