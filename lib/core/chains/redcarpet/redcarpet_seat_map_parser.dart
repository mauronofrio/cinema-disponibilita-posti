import 'dart:convert';

import '../../models/seat_map.dart';

/// Bundles both raw responses into one argument so parsing can still happen
/// in a single `compute()` call if the SVG turns out large enough to
/// warrant it (same reasoning as the other two chains' seat map payloads).
class RedCarpetSeatMapPayload {
  const RedCarpetSeatMapPayload({
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
  });

  final String seatId;
  final String row;
  final String seatNumber;
  final String area;
  final double x;
  final double y;

  /// Accessibility/wheelchair seats carry an extra `special userhide` class
  /// alongside `posto` (confirmed live: always the two seats at either end
  /// of the row farthest from the screen) - not offered through the normal
  /// booking flow at all ("userhide"). The old class match required the
  /// attribute to be *exactly* `posto`, which silently dropped every one of
  /// these seats from the parsed room entirely (a gap in the grid, not just
  /// a wrong color) since their real class value never matched.
  final bool isAccessibility;
}

final _seatGroupRe = RegExp(
  r"""<g class=['"]([^'"]*)['"][^>]*data-area=['"]([^'"]*)['"][^>]*data-row=['"]([^'"]*)['"][^>]*data-seat=['"]([^'"]*)['"][^>]*>\s*<rect[^>]*id=['"]([^'"]+)['"][^>]*x=['"]([\d.]+)['"][^>]*y=['"]([\d.]+)['"]""",
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

/// `reserved` gets its own [SeatStatus] (RedCarpet's own legend calls it
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
/// row/column numbers - both column order (by x) and row order (by y) are
/// derived from real position rather than trusting a label, the same rule
/// already applied to columns and now extended to rows too: alphabetical
/// row-label order turned out to run screen-to-back backwards in the one
/// real room checked (row "A" sits at the *highest* y, i.e. the row
/// farthest from the screen, confirmed live - not the front row the
/// alphabetical assumption implied). `data-seat` itself is not reliable for
/// column ordering either: observed to *decrease* left-to-right in at
/// least one real room, so it's only ever used for the visible label, never
/// for placement.
SeatMap parseRedCarpetSeatMap(RedCarpetSeatMapPayload payload) {
  final rawSeats = <_RawSeat>[];
  for (final match in _seatGroupRe.allMatches(payload.theaterSvg)) {
    final classAttr = match.group(1)!;
    rawSeats.add(
      _RawSeat(
        area: match.group(2)!,
        row: match.group(3)!,
        seatNumber: match.group(4)!,
        seatId: match.group(5)!,
        x: double.parse(match.group(6)!),
        y: double.parse(match.group(7)!),
        isAccessibility:
            classAttr.contains('special') || classAttr.contains('userhide'),
      ),
    );
  }

  final occupancy = json.decode(payload.occupancyJson) as Map<String, dynamic>;
  final busyBySeatId = <String, Set<String>>{
    for (final key in _busyKeys)
      key: ((occupancy[key] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toSet(),
  };

  final distinctX = rawSeats.map((s) => s.x).toSet().toList()..sort();
  final columnForX = {
    for (var i = 0; i < distinctX.length; i++) distinctX[i]: i + 1,
  };
  final totalColumns = distinctX.length;

  final byRow = <String, List<_RawSeat>>{};
  for (final seat in rawSeats) {
    byRow.putIfAbsent(seat.row, () => []).add(seat);
  }
  // Every seat in a row shares the same y in practice, but average defends
  // against a room where that's not quite exact.
  double averageY(List<_RawSeat> seats) =>
      seats.map((s) => s.y).reduce((a, b) => a + b) / seats.length;
  final rowLabels = byRow.keys.toList()
    ..sort((a, b) => averageY(byRow[a]!).compareTo(averageY(byRow[b]!)));

  final rows = rowLabels.map((rowLabel) {
    final rowIndex = rowLabel.isEmpty ? 0 : rowLabel.codeUnitAt(0);
    final slots = List<Seat?>.filled(totalColumns, null);
    for (final raw in byRow[rowLabel]!) {
      final column = columnForX[raw.x]!;
      slots[column - 1] = Seat(
        rowIndex: rowIndex,
        columnIndex: column,
        name: '$rowLabel${raw.seatNumber}',
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
