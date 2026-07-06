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
  });

  factory Seat.fromJson(Map<String, dynamic> json) {
    return Seat(
      rowIndex: json['rowIndex'] as int,
      columnIndex: json['columnIndex'] as int,
      name: (json['name'] as String?) ?? '',
      status: seatStatusFromCode((json['seatStatus'] as num).toInt()),
      areaCategoryCode: (json['areaCategoryCode'] as String?) ?? '',
    );
  }

  final int rowIndex;
  final int columnIndex;
  final String name;
  final SeatStatus status;
  final String areaCategoryCode;
}

class SeatRow {
  const SeatRow({
    required this.rowLabel,
    required this.rowIndex,
    required this.seats,
  });

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
}
