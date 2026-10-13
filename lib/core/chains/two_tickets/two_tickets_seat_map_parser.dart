import 'dart:convert';
import 'dart:math' as math;

import '../../models/seat_map.dart';

class TwoTicketsSector {
  const TwoTicketsSector({
    required this.id,
    required this.name,
    required this.hall,
    required this.isNumbered,
    required this.freeSeats,
    required this.capacity,
  });

  final int id;
  final String name;
  final String hall;
  final bool isNumbered;
  final int freeSeats;

  /// `capienza` - careful: in a multi-sector room this is the whole room's
  /// capacity, repeated on every sector (Orfeo Taranto: 773 on all 7).
  final int capacity;
}

/// Parses `/api/sala/settori`. Only the fields below are read - the
/// response also carries the cinema's payment-gateway credentials (the
/// site's bug), which are deliberately never touched.
List<TwoTicketsSector> parseTwoTicketsSectors(String body) {
  final json = jsonDecode(body) as Map<String, dynamic>;
  if (json['esito'] != 'OK') return const [];
  return [
    for (final raw in (json['settori'] as List<dynamic>? ?? const []))
      if (raw is Map<String, dynamic> && raw['idSettore'] is num)
        TwoTicketsSector(
          id: (raw['idSettore'] as num).toInt(),
          name: (raw['descrizione'] as String?)?.trim() ?? '',
          hall: (raw['sala'] as String?)?.trim() ?? '',
          isNumbered:
              raw['hasNumerazione'] == true && '${raw['modVend']}' != '1',
          freeSeats: (raw['totPostiLiberi'] as num?)?.toInt() ?? 0,
          capacity: (raw['capienza'] as num?)?.toInt() ?? 0,
        ),
  ];
}

class TwoTicketsSeatMapPayload {
  const TwoTicketsSeatMapPayload({
    required this.sectors,
    required this.seatsJsonBySectorId,
  });

  final List<TwoTicketsSector> sectors;

  /// Raw `/api/sala/posti` bodies, numbered sectors only.
  final Map<int, String> seatsJsonBySectorId;
}

/// Same classification as the site's own map renderer (checkout JS,
/// `renderMappa`): a gap if `fila == '-'`, `stato == 0` or `isBuco`; free
/// if `stato == 2` or `isLibero`; anything else is taken (sold seats are
/// `stato 201` / `isVenduto`, verified live). Unknown future states
/// therefore read as taken - the safe direction for "can I get a seat".
Seat? _seat(Map<String, dynamic> p, int row, int col, String sectorCode) {
  final fila = '${p['fila'] ?? '-'}';
  final stato = (p['stato'] as num?)?.toInt() ?? 0;
  if (fila == '-' || stato == 0 || p['isBuco'] == true) return null;
  final accessible =
      p['isHandicap'] == true || ((p['handicap'] as num?) ?? 0) != 0;
  final notForSale = ((p['nonVendibile'] as num?) ?? 0) != 0;
  final free = stato == 2 || p['isLibero'] == true;
  final status = notForSale
      ? SeatStatus.special
      : free
      ? (accessible ? SeatStatus.accessibility : SeatStatus.available)
      : SeatStatus.occupied;
  return Seat(
    rowIndex: row,
    columnIndex: col,
    name: (p['codicePosto'] as String?) ?? '$fila${p['colonna'] ?? ''}',
    status: status,
    areaCategoryCode: sectorCode,
    isAccessibility: accessible,
  );
}

/// A row's two blocks can be spelled differently (`AA13…AA1 · A1…A13` -
/// verified on Moderno Anzio): they are one row, so the shortest spelling
/// is the label, while each seat keeps its full code as its name.
String _rowLabel(Iterable<Map<String, dynamic>> cells) {
  String? best;
  for (final p in cells) {
    final fila = '${p['fila'] ?? '-'}';
    if (fila == '-' || p['isBuco'] == true) continue;
    if (best == null || fila.length < best.length) best = fila;
  }
  return best ?? '';
}

SeatMap buildTwoTicketsSeatMap(TwoTicketsSeatMapPayload payload) {
  final numbered = payload.sectors.where((s) => s.isNumbered).toList();
  final unnumbered = payload.sectors.where((s) => !s.isNumbered).toList();
  final rows = <SeatRow>[];
  final categories = <AreaCategory>[];
  var totalColumns = 0;

  for (final sector in numbered) {
    final body = payload.seatsJsonBySectorId[sector.id];
    if (body == null) continue;
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['esito'] != 'OK') continue;
    final cols = (json['colonneSettore'] as num?)?.toInt() ?? 0;
    final rowCount = (json['righeSettore'] as num?)?.toInt() ?? 0;
    final cells = (json['tuttiIPosti'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (cols == 0 || rowCount == 0) continue;
    if (cols > totalColumns) totalColumns = cols;
    final code = '${sector.id}';
    if (rows.isNotEmpty) {
      // One blank row between sectors, so stacked sectors (stalls, then
      // galleries, then boxes) read as separate blocks.
      rows.add(SeatRow(rowLabel: '', rowIndex: rows.length, seats: const []));
    }
    for (var r = 0; r < rowCount; r++) {
      final start = r * cols;
      if (start >= cells.length) break;
      final rowCells = cells.sublist(
        start,
        math.min(start + cols, cells.length),
      );
      rows.add(
        SeatRow(
          rowLabel: _rowLabel(rowCells),
          rowIndex: rows.length,
          seats: [
            for (var c = 0; c < rowCells.length; c++)
              _seat(rowCells[c], r, c, code),
          ],
        ),
      );
    }
    categories.add(
      AreaCategory(
        code: code,
        name: sector.name,
        color: null,
        isSoldOut: sector.freeSeats == 0,
      ),
    );
  }

  final singleSector = payload.sectors.length == 1;
  return SeatMap(
    screenLabel: payload.sectors.isEmpty ? '' : payload.sectors.first.hall,
    totalRows: rows.length,
    totalColumns: totalColumns,
    rows: rows,
    areaCategories: categories,
    unnumberedSectors: [
      for (final s in unnumbered)
        UnnumberedSector(
          name: s.name,
          freeSeats: s.freeSeats,
          capacity: singleSector && s.capacity > 0 ? s.capacity : null,
        ),
    ],
  );
}
