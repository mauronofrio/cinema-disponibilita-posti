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
  });

  final String seatId;
  final String row;
  final String seatNumber;
  final String area;
  final double x;
}

final _seatGroupRe = RegExp(
  r"""<g class=['"]posto['"][^>]*data-area=['"]([^'"]*)['"][^>]*data-row=['"]([^'"]*)['"][^>]*data-seat=['"]([^'"]*)['"][^>]*>\s*<rect[^>]*id=['"]([^'"]+)['"][^>]*x=['"]([\d.]+)['"]""",
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
SeatStatus _statusFor(String seatId, Map<String, Set<String>> busyBySeatId) {
  if (busyBySeatId['reserved']!.contains(seatId)) return SeatStatus.reserved;
  for (final key in _busyKeys) {
    if (busyBySeatId[key]!.contains(seatId)) return SeatStatus.occupied;
  }
  return SeatStatus.available;
}

/// Parses a `theater/{id}.svg` layout together with a `seats/{id}`
/// occupancy response into the same [SeatMap] shape the UI already renders
/// for the other two chains.
///
/// The SVG gives each seat's exact x position rather than a discrete column
/// number - column order here is derived by collecting every distinct x
/// seen across the whole room and ranking them, the same "trust the real
/// position, not a numbered field" rule as the other chains' seat rows,
/// just applied to continuous coordinates instead of an integer index
/// (`data-seat` itself is not reliable for ordering: it's observed to
/// *decrease* left-to-right in at least one real room, so it's only ever
/// used for the visible label, never for placement).
SeatMap parseRedCarpetSeatMap(RedCarpetSeatMapPayload payload) {
  final rawSeats = <_RawSeat>[];
  for (final match in _seatGroupRe.allMatches(payload.theaterSvg)) {
    rawSeats.add(
      _RawSeat(
        area: match.group(1)!,
        row: match.group(2)!,
        seatNumber: match.group(3)!,
        seatId: match.group(4)!,
        x: double.parse(match.group(5)!),
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
  final rowLabels = byRow.keys.toList()..sort();

  final rows = rowLabels.map((rowLabel) {
    final rowIndex = rowLabel.isEmpty ? 0 : rowLabel.codeUnitAt(0);
    final slots = List<Seat?>.filled(totalColumns, null);
    for (final raw in byRow[rowLabel]!) {
      final column = columnForX[raw.x]!;
      slots[column - 1] = Seat(
        rowIndex: rowIndex,
        columnIndex: column,
        name: '$rowLabel${raw.seatNumber}',
        status: _statusFor(raw.seatId, busyBySeatId),
        areaCategoryCode: raw.area,
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
