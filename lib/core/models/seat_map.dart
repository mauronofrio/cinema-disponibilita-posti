import 'dart:convert';

/// Seat status codes as returned by the `seatStatus` field, confirmed against
/// the live API (see research/samples/seats_resp.json) and cross-checked with
/// the prior userscript at github.com/mauronofrio/TheSpace_Fast_Seat_Check.
enum SeatStatus {
  available,
  occupied,
  reserved,
  special,
  accessibility,
  unknown,
}

SeatStatus seatStatusFromCode(int code) {
  switch (code) {
    case 0:
      return SeatStatus.available;
    case 1:
    case 2:
    case 9:
      return SeatStatus.occupied;
    case 4:
    case 8:
      return SeatStatus.reserved;
    case 7:
      return SeatStatus.special;
    case 11:
      return SeatStatus.accessibility;
    default:
      return SeatStatus.unknown;
  }
}

/// A single seat, trimmed down to only the fields the UI needs. The raw API
/// response nests a large `sitecoreSeatStatus` object (Sitecore/Vista GUIDs,
/// timestamps, per-status icon sets) per seat that roughly triples the
/// payload size for no benefit here — it is intentionally dropped during
/// parsing rather than carried around in memory.
class Seat {
  const Seat({
    required this.rowIndex,
    required this.columnIndex,
    required this.name,
    required this.status,
    required this.areaCategoryCode,
    this.isAccessibility = false,
  });

  factory Seat.fromJson(Map<String, dynamic> json) {
    final status = seatStatusFromCode((json['seatStatus'] as num).toInt());
    return Seat(
      rowIndex: json['rowIndex'] as int,
      columnIndex: json['columnIndex'] as int,
      name: (json['name'] as String?) ?? '',
      status: status,
      areaCategoryCode: (json['areaCategoryCode'] as String?) ?? '',
      isAccessibility: status == SeatStatus.accessibility,
    );
  }

  final int rowIndex;
  final int columnIndex;
  final String name;
  final SeatStatus status;
  final String areaCategoryCode;

  /// Whether this seat is a wheelchair-accessible spot, as a fixed property
  /// of the seat itself - independent of [status], which for UCI collapses
  /// to plain `occupied` when an accessibility seat happens to be taken for
  /// this particular showing (see uci_seat_map_parser.dart). Occupancy
  /// counts need this separate flag to exclude accessibility seats
  /// consistently, not just the ones that happen to still be free.
  final bool isAccessibility;
}

class SeatRow {
  const SeatRow({
    required this.rowLabel,
    required this.rowIndex,
    required this.seats,
  });

  /// The raw `columns` array is rendered in the exact order the API sends
  /// it, with `null` entries preserved as same-sized gaps - deliberately
  /// *not* reordered by `columnIndex`. An earlier version of this code
  /// rebuilt each row by placing seats at their own `columnIndex`, assuming
  /// array order was unreliable; that assumption was wrong and produced a
  /// mirrored/incorrect layout. The reference implementation this app is
  /// modeled on (github.com/mauronofrio/TheSpace_Fast_Seat_Check, a
  /// userscript validated against the real site across many rooms) simply
  /// trusts array order, and so does this.
  factory SeatRow.fromJson(Map<String, dynamic> json) {
    return SeatRow(
      rowLabel: (json['rowLabel'] as String?) ?? '',
      rowIndex: json['rowIndex'] as int,
      seats: (json['columns'] as List<dynamic>? ?? const [])
          .map(
            (c) => c == null ? null : Seat.fromJson(c as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  final String rowLabel;
  final int rowIndex;
  final List<Seat?> seats;
}

class AreaCategory {
  const AreaCategory({
    required this.code,
    required this.name,
    required this.color,
    required this.isSoldOut,
  });

  factory AreaCategory.fromJson(Map<String, dynamic> json) {
    return AreaCategory(
      code: json['areaCategoryCode'] as String,
      name: (json['areaName'] as String?) ?? '',
      color: json['areaColor'] as String?,
      isSoldOut: (json['isSoldOut'] as bool?) ?? false,
    );
  }

  final String code;
  final String name;
  final String? color;
  final bool isSoldOut;
}

class SeatMap {
  const SeatMap({
    required this.screenLabel,
    required this.totalRows,
    required this.totalColumns,
    required this.rows,
    required this.areaCategories,
  });

  /// Decodes and parses the raw `{"result": {...}}` API response body in one
  /// step. Designed to run inside `compute()` (a background isolate) since
  /// the source JSON can be several hundred KB - both `jsonDecode` and the
  /// object mapping below are real UI-thread jank if run inline.
  factory SeatMap.fromApiResponseJson(String responseBody) {
    final apiResponse = json.decode(responseBody) as Map<String, dynamic>;
    final result = apiResponse['result'] as Map<String, dynamic>;
    final seatingData = result['seatingData'] as Map<String, dynamic>;
    return SeatMap(
      screenLabel: (seatingData['screenLabel'] as String?) ?? '',
      totalRows: (seatingData['totalRows'] as num).toInt(),
      totalColumns: (seatingData['totalColumns'] as num).toInt(),
      // Rows are rendered in raw array order too, for the same reason as
      // columns above - the reference userscript just does
      // `seatRows.forEach(...)` with no sort.
      rows: (result['seatRows'] as List<dynamic>? ?? const [])
          .map((r) => SeatRow.fromJson(r as Map<String, dynamic>))
          .toList(),
      areaCategories: (result['areaCategories'] as List<dynamic>? ?? const [])
          .map((c) => AreaCategory.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  final String screenLabel;
  final int totalRows;
  final int totalColumns;
  final List<SeatRow> rows;
  final List<AreaCategory> areaCategories;

  AreaCategory? categoryFor(String code) {
    for (final category in areaCategories) {
      if (category.code == code) return category;
    }
    return null;
  }

  /// Every real seat in the room (nulls are aisle gaps, not seats),
  /// excluding accessibility and [SeatStatus.special] seats - the
  /// "Occupati X/Y" summary is about ordinary seat availability, and a
  /// handful of wheelchair or restricted/not-for-sale spots would skew both
  /// the count and the percentage without meaning much either way for
  /// someone not booking one. [SeatStatus.special] seats are never actually
  /// bookable regardless of chain (confirmed live on Multisala Massimo -
  /// Lecce: 253 of one room's 701 seats are a whole upper-gallery section
  /// permanently marked this way, not individually occupied/free) - without
  /// this they'd always count as "occupied" (`totalSeatCount -
  /// availableSeatCount`), making a room using them look far busier than it
  /// really is even when genuinely empty.
  int get totalSeatCount => rows.fold(
    0,
    (sum, row) =>
        sum +
        row.seats
            .whereType<Seat>()
            .where((s) => !s.isAccessibility && s.status != SeatStatus.special)
            .length,
  );

  /// Matches the reference implementation's own notion of "free": exactly
  /// `status == available`, everything else (occupied, reserved, sold-out
  /// areas, ...) counts against it. Accessibility and [SeatStatus.special]
  /// seats are excluded here too, same reasoning as [totalSeatCount].
  int get availableSeatCount => rows.fold(
    0,
    (sum, row) =>
        sum +
        row.seats
            .whereType<Seat>()
            .where(
              (s) => !s.isAccessibility && s.status == SeatStatus.available,
            )
            .length,
  );

  int get occupiedSeatCount => totalSeatCount - availableSeatCount;

  /// 0.0-1.0, occupied over total; 0 for an empty/degenerate room rather
  /// than dividing by zero.
  double get occupancyRatio =>
      totalSeatCount == 0 ? 0 : occupiedSeatCount / totalSeatCount;
}
