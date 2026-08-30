import 'dart:convert';

import '../../models/seat_map.dart';
import '../parsing_utils.dart';

/// Bundles both raw response bodies into one argument so parsing can still
/// happen in a single `compute()` call - same reasoning as
/// [UciSeatMapPayload]/`SeatMap.fromApiResponseJson`.
class WebticSeatMapPayload {
  const WebticSeatMapPayload({
    required this.mapSeatsResponseBody,
    required this.occupancyResponseBody,
  });

  final String mapSeatsResponseBody;
  final String occupancyResponseBody;
}

/// Confirmed live on both Notorious Cinemas and Giometti Cinema: a
/// `getOccupancy` response always echoes the room it's for as `idsala`,
/// even though the request itself only ever took a `PerformanceId` - no
/// separate "which room does this showtime play in" lookup is needed at
/// all, `getOccupancy` is called first and this is read off its response
/// before calling `getMapSeats`.
int parseWebticScreenIdFromOccupancy(String occupancyResponseBody) {
  final occupancyJson =
      json.decode(occupancyResponseBody) as Map<String, dynamic>;
  final occupancy =
      (occupancyJson['DS'] as Map<String, dynamic>)['Occupancy']
          as Map<String, dynamic>;
  return (occupancy['idsala'] as num).toInt();
}

/// Confirmed live on Giometti Cinema (Pesaro, room "2"/idsala 74): the
/// wheelchair spot itself never appears in `posti` at all - it's a genuine
/// gap in the `colonna` numbering (columns 9-11 of row A missing entirely
/// in that room, flanked by two `ACCOMPAGNATORE` seats at 8 and 12) - so
/// nothing needs to be done for the wheelchair spot itself, the existing
/// gap-preserving grid already renders it correctly as empty space. Only
/// the companion seats next to it need their own status.
const _accessibilityRelatedSeatTypes = {'DISABILE', 'ACCOMPAGNATORE'};

SeatStatus _statusFor(String seatType, bool isOccupied) {
  // Occupancy only lists seats that AREN'T free (`BLOCCATO` confirmed live;
  // other statuses like a completed sale presumably exist too) - anything
  // absent from it is available, same model as UCI's own Webtic proxy.
  if (isOccupied) return SeatStatus.occupied;
  if (_accessibilityRelatedSeatTypes.contains(seatType)) {
    return SeatStatus.accessibility;
  }
  switch (seatType) {
    case 'RISERVATO':
      return SeatStatus.reserved;
    default:
      return SeatStatus.available;
  }
}

/// Merges a `getMapSeats` response (the room's physical layout) with a
/// `getOccupancy` response (which of those seats aren't free right now)
/// into the same [SeatMap] model the UI already renders for every other
/// chain.
///
/// Field names are the platform's own native Italian ones (`fila`,
/// `colonna`, `idposto`, `tipologia`, `settore`) - distinct from
/// `uci_seat_map_parser.dart`, which reads the English names UCI's own
/// Webtic proxy translates them to, even though both describe the same
/// underlying seats.
SeatMap parseWebticSeatMap(WebticSeatMapPayload payload) {
  final mapSeatsJson =
      json.decode(payload.mapSeatsResponseBody) as Map<String, dynamic>;
  final occupancyJson =
      json.decode(payload.occupancyResponseBody) as Map<String, dynamic>;

  final mapSeats =
      (mapSeatsJson['DS'] as Map<String, dynamic>)['MapSeats']
          as Map<String, dynamic>;
  final rawSeats = (mapSeats['posti'] as List<dynamic>? ?? const [])
      .cast<Map<String, dynamic>>();

  final occupancy =
      (occupancyJson['DS'] as Map<String, dynamic>)['Occupancy']
          as Map<String, dynamic>;
  final occupiedSeatIds = (occupancy['posti'] as List<dynamic>? ?? const [])
      .cast<Map<String, dynamic>>()
      .map((s) => s['idposto'] as String)
      .toSet();

  var totalColumns = 0;
  final byRow = <int, List<Map<String, dynamic>>>{};
  for (final seat in rawSeats) {
    final row = (seat['fila'] as num).toInt();
    final column = (seat['colonna'] as num).toInt();
    if (column > totalColumns) totalColumns = column;
    byRow.putIfAbsent(row, () => []).add(seat);
  }

  final rowIndexes = byRow.keys.toList()..sort();
  final rows = rowIndexes.map((rowIndex) {
    final seatsInRow = byRow[rowIndex]!;
    final slots = List<Seat?>.filled(totalColumns, null);
    for (final seatJson in seatsInRow) {
      final column = (seatJson['colonna'] as num).toInt();
      final seatId = seatJson['idposto'] as String;
      final seatType = (seatJson['tipologia'] as String?) ?? '';
      slots[column - 1] = Seat(
        rowIndex: rowIndex,
        columnIndex: column,
        name: (seatJson['alias'] as String?) ?? seatId,
        status: _statusFor(seatType, occupiedSeatIds.contains(seatId)),
        areaCategoryCode: (seatJson['settore'] as String?) ?? '',
        // Independent of `status` above, same reasoning as UCI: a
        // currently-occupied accessibility seat still reports
        // status == occupied, but stays an accessibility seat for
        // occupancy-count purposes.
        isAccessibility: _accessibilityRelatedSeatTypes.contains(seatType),
        // `tipologia` describes the seat in the room layout, not its state
        // for this showing, so RISERVATO here is permanent - same reasoning
        // as UCI's own `SeatType` (both read the same Webtic backend). See
        // [Seat.isPermanentlyReserved].
        isPermanentlyReserved: seatType == 'RISERVATO',
      );
    }
    // Same bug UCI's own Webtic proxy already had (see
    // uci_seat_map_parser.dart's rowLabelByMajorityPrefix doc comment) on
    // the same underlying secure.webtic.it backend, reachable natively
    // here on Notorious/Giometti/Cineplexx rooms too: `idposto`'s prefix
    // isn't reliably the row's own real label when read off just the
    // first seat, since a row's accessibility seat(s) can sort ahead of
    // its regular ones in the raw array.
    final rowLabel = rowLabelByMajorityPrefix(
      seatsInRow.map((seatJson) => seatJson['idposto'] as String),
    );
    return SeatRow(rowLabel: rowLabel, rowIndex: rowIndex, seats: slots);
  }).toList();

  // `gruppi` (sector groupings with a name/color) has only ever been seen
  // empty so far (every Notorious Cinemas room checked has a single "PT"
  // sector) - falling back to bare sector codes with no name/color rather
  // than guessing `gruppi`'s field names against zero real examples.
  final sectorCodes = rawSeats
      .map((s) => (s['settore'] as String?) ?? '')
      .where((s) => s.isNotEmpty)
      .toSet();

  return SeatMap(
    screenLabel: '',
    totalRows: rows.length,
    totalColumns: totalColumns,
    rows: rows,
    areaCategories: sectorCodes
        .map(
          (code) => AreaCategory(
            code: code,
            name: '',
            color: null,
            isSoldOut: false,
          ),
        )
        .toList(),
  );
}
