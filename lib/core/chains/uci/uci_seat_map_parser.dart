import 'dart:convert';

import '../../models/seat_map.dart';
import '../parsing_utils.dart';

/// Bundles both raw response bodies into one argument so parsing can still
/// happen in a single `compute()` call, same reasoning as
/// [SeatMap.fromApiResponseJson] for The Space.
class UciSeatMapPayload {
  const UciSeatMapPayload({
    required this.screenResponseBody,
    required this.occupancyResponseBody,
  });

  final String screenResponseBody;
  final String occupancyResponseBody;
}

SeatStatus _statusFor(
  String seatId,
  String seatType,
  Set<String> occupiedSeatIds,
) {
  // Occupancy only lists seats that AREN'T free (`BLOCCATO` mid-purchase by
  // someone else, `ACQUISTO` already bought) - anything absent from it is
  // available, the inverse of The Space's model where every seat carries an
  // explicit status including "available".
  if (occupiedSeatIds.contains(seatId)) return SeatStatus.occupied;
  switch (seatType) {
    case 'DISABILE':
      return SeatStatus.accessibility;
    case 'RISERVATO':
      return SeatStatus.reserved;
    default:
      return SeatStatus.available;
  }
}

/// Most UCI rows share one numeric `Row` index with a handful of dedicated
/// accessibility seats too (`SeatId` prefix "HX", `SeatAlias` "P.D.") -
/// confirmed live at UCI Bicocca Milano, where a 14-seat "G" row's two
/// wheelchair spots (`HX/1`, `HX/2`) appear *first* in the raw array,
/// ahead of the other 12 "G/..." seats. See [rowLabelByMajorityPrefix]
/// (shared with Webtic, the same underlying platform for this - see
/// `webtic_seat_map_parser.dart`) for why a majority vote fixes this.
String _rowLabelFor(List<Map<String, dynamic>> seatsInRow) {
  return rowLabelByMajorityPrefix(
    seatsInRow.map((seatJson) => seatJson['SeatId'] as String),
  );
}

/// Merges a `Screen` response (the room's physical layout - every seat with
/// its row/column/type/sector) with an `Occupancy` response (which of those
/// seats aren't free right now) into the same [SeatMap] model the UI already
/// renders for The Space.
///
/// Screen gives sparse (Row, Column) coordinates rather than a pre-ordered
/// per-row array with gap placeholders (what The Space provides and what
/// [SeatRow] otherwise just trusts as-is) - so here, unlike there, building
/// each row's placeholder array by explicit column position is the correct
/// approach, not a re-sort of already-reliable order.
SeatMap parseUciSeatMap(UciSeatMapPayload payload) {
  final screenJson =
      json.decode(payload.screenResponseBody) as Map<String, dynamic>;
  final occupancyJson =
      json.decode(payload.occupancyResponseBody) as Map<String, dynamic>;

  final screen =
      (screenJson['Data'] as Map<String, dynamic>)['Screen']
          as Map<String, dynamic>;
  final rawSeats = (screen['Seats'] as List<dynamic>? ?? const [])
      .cast<Map<String, dynamic>>();
  final sectors = (screen['Sectors'] as List<dynamic>? ?? const [])
      .cast<Map<String, dynamic>>();

  final occupancy =
      (occupancyJson['Data'] as Map<String, dynamic>)['Occupancy']
          as Map<String, dynamic>;
  final occupancySeats = (occupancy['Seats'] as List<dynamic>? ?? const [])
      .cast<Map<String, dynamic>>();
  final occupiedSeatIds = occupancySeats
      .map((s) => s['SeatId'] as String)
      .toSet();

  var totalColumns = 0;
  final byRow = <int, List<Map<String, dynamic>>>{};
  for (final seat in rawSeats) {
    final row = (seat['Row'] as num).toInt();
    final column = (seat['Column'] as num).toInt();
    if (column > totalColumns) totalColumns = column;
    byRow.putIfAbsent(row, () => []).add(seat);
  }

  final rowIndexes = byRow.keys.toList()..sort();
  final rows = rowIndexes.map((rowIndex) {
    final seatsInRow = byRow[rowIndex]!;
    final slots = List<Seat?>.filled(totalColumns, null);
    for (final seatJson in seatsInRow) {
      final column = (seatJson['Column'] as num).toInt();
      final seatId = seatJson['SeatId'] as String;
      final seatType = (seatJson['SeatType'] as String?) ?? '';
      slots[column - 1] = Seat(
        rowIndex: rowIndex,
        columnIndex: column,
        name: (seatJson['SeatAlias'] as String?) ?? seatId,
        status: _statusFor(seatId, seatType, occupiedSeatIds),
        areaCategoryCode: (seatJson['SectorId'] as String?) ?? '',
        // Independent of `status` above: a DISABILE seat that's currently
        // taken still reports status == occupied (see _statusFor), but is
        // still an accessibility seat for occupancy-count purposes.
        isAccessibility: seatType == 'DISABILE',
        // `SeatType` comes from the Screen (room layout) response, not the
        // Occupancy one, so RISERVATO here means "withheld from sale in
        // every showing" - not "taken for this one". See
        // [Seat.isPermanentlyReserved] for why that distinction can't live
        // in the shared counters.
        isPermanentlyReserved: seatType == 'RISERVATO',
      );
    }
    return SeatRow(
      rowLabel: _rowLabelFor(seatsInRow),
      rowIndex: rowIndex,
      seats: slots,
    );
  }).toList();

  return SeatMap(
    screenLabel: '',
    totalRows: rows.length,
    totalColumns: totalColumns,
    rows: rows,
    areaCategories: sectors
        .map(
          (s) => AreaCategory(
            code: (s['SectorId'] as String?) ?? '',
            name: (s['SectorName'] as String?) ?? '',
            color: s['SectorColor'] as String?,
            isSoldOut: false,
          ),
        )
        .toList(),
  );
}
