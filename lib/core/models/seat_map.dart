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
    this.isPermanentlyReserved = false,
  });

  factory Seat.fromJson(Map<String, dynamic> json) {
    final status = seatStatusFromCode((json['seatStatus'] as num).toInt());
    return Seat(
      // Neither of these is actually read anywhere in lib/features/ - the
      // grid renders row.seats positionally and keys off SeatRow.rowLabel,
      // never rowIndex/columnIndex (confirmed with a grep before making
      // this change). Still given the same safe-fallback treatment as
      // every neighbouring field rather than a hard cast, so a malformed
      // or missing value here can never crash a seat map load over data
      // nothing actually consumes.
      rowIndex: (json['rowIndex'] as int?) ?? 0,
      columnIndex: (json['columnIndex'] as int?) ?? 0,
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

  /// Whether this seat is reserved as a **fixed property of the room** -
  /// permanently withheld from sale for every showing (season-ticket
  /// holders, staff, press), rather than reserved for this one screening.
  ///
  /// Same shape and purpose as [isAccessibility]: a fixed fact about the
  /// seat, kept separate from [status] so the counters can exclude it
  /// while the UI still labels it accurately as "Riservato".
  ///
  /// This distinction is unavoidable because `SeatStatus.reserved` means
  /// two genuinely different things depending on the chain, and only the
  /// parser knows which:
  ///  - On The Space it's a *per-showing* state (codes 4/8 on that day's
  ///    seat response), so it correctly counts as occupied - those seats
  ///    are unavailable tonight but were sellable in principle.
  ///  - On UCI and Webtic it comes from `SeatType` in the **room layout**
  ///    response, not the occupancy one (see PROJECT_NOTES.md: "`SeatType`
  ///    è una proprietà fissa del posto, NON lo stato di occupazione per
  ///    quello spettacolo"). Counting those as occupied made a real
  ///    242-seat UCI room with 28 such seats report "Occupati 28/240 ·
  ///    12%" with zero tickets sold - permanently 12 points busier than
  ///    reality, on every single showing.
  ///
  /// So the exclusion belongs here, set by the parsers that know, and NOT
  /// as a blanket `status != reserved` rule in the counters below - that
  /// would silently stop counting The Space's genuinely-taken seats.
  final bool isPermanentlyReserved;
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
      // Not read anywhere in lib/features/ either (the grid keys off
      // rowLabel, not rowIndex) - same reasoning as Seat.rowIndex/
      // columnIndex above, given a safe fallback instead of a hard cast.
      rowIndex: (json['rowIndex'] as int?) ?? 0,
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
      // Unlike rowIndex/columnIndex above, this one IS read - see
      // area_legend.dart's visibleAreaCategories, matched against each
      // seat's own areaCategoryCode. A missing/malformed value here just
      // means that category never matches any seat (the same as any
      // other made-up code would), not a crash - so it gets the same
      // safe-fallback treatment as every neighbouring field instead of a
      // hard cast.
      code: (json['areaCategoryCode'] as String?) ?? '',
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
  // Not `const`: `_categoriesByCode` below is a mutable memoization field
  // for `categoryFor`, and a const constructor requires every field final.
  SeatMap({
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
    // Rows are rendered in raw array order too, for the same reason as
    // columns above - the reference userscript just does
    // `seatRows.forEach(...)` with no sort.
    final rows = (result['seatRows'] as List<dynamic>? ?? const [])
        .map((r) => SeatRow.fromJson(r as Map<String, dynamic>))
        .toList();
    return SeatMap(
      screenLabel: (seatingData['screenLabel'] as String?) ?? '',
      // `seatingData.totalRows`/`totalColumns` used to be trusted as-is, but
      // the live API stopped sending them entirely (confirmed on multiple
      // cinemas - `seatingData` now only ever has `screenLabel`), which
      // turned every seat map load into a parse failure. Every other chain's
      // parser (webtic/uci/18tickets) already derives these from the actual
      // rows/columns instead of a server-declared total, so this does the
      // same rather than trusting a field that may not be there.
      totalRows: rows.length,
      totalColumns: rows.fold(0, (max, row) => row.seats.length > max ? row.seats.length : max),
      rows: rows,
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

  /// Lazily built and cached on first lookup: `areaCategories` is small
  /// today but `categoryFor` is called once per rendered seat cell (hundreds
  /// per room), so an O(n) scan per call is worth avoiding with an O(1) map
  /// built once. Plain nullable field rather than `late final`, since
  /// `SeatMap` has a `const` constructor and `late final` isn't allowed
  /// there - this is manual memoization instead.
  Map<String, AreaCategory>? _categoriesByCode;

  AreaCategory? categoryFor(String code) {
    final map = _categoriesByCode ??= {
      for (final category in areaCategories) category.code: category,
    };
    return map[code];
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
  /// [Seat.isPermanentlyReserved] seats are excluded for exactly the same
  /// reason as [SeatStatus.special] ones: never on sale for any showing,
  /// so counting them as "occupied" overstates how full the room is.
  int get totalSeatCount => rows.fold(
    0,
    (sum, row) =>
        sum +
        row.seats
            .whereType<Seat>()
            .where(
              (s) =>
                  !s.isAccessibility &&
                  !s.isPermanentlyReserved &&
                  s.status != SeatStatus.special,
            )
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
              (s) =>
                  !s.isAccessibility &&
                  !s.isPermanentlyReserved &&
                  s.status == SeatStatus.available,
            )
            .length,
  );

  int get occupiedSeatCount => totalSeatCount - availableSeatCount;

  /// 0.0-1.0, occupied over total; 0 for an empty/degenerate room rather
  /// than dividing by zero.
  double get occupancyRatio =>
      totalSeatCount == 0 ? 0 : occupiedSeatCount / totalSeatCount;

  /// Same numbers as [totalSeatCount]/[occupiedSeatCount]/[occupancyRatio]
  /// combined, but computed in a single pass over every row instead of
  /// three (six, counting [occupiedSeatCount] and [occupancyRatio] each
  /// recomputing [totalSeatCount] internally). Callers that need all three
  /// - like `OccupancySummary` - should use this instead of reading the
  /// separate getters back to back.
  OccupancyStats get occupancyStats {
    var total = 0;
    var available = 0;
    for (final row in rows) {
      for (final seat in row.seats) {
        if (seat == null ||
            seat.isAccessibility ||
            seat.status == SeatStatus.special) {
          continue;
        }
        total++;
        if (seat.status == SeatStatus.available) available++;
      }
    }
    final occupied = total - available;
    return OccupancyStats(
      total: total,
      occupied: occupied,
      ratio: total == 0 ? 0 : occupied / total,
    );
  }
}

/// Bundled result of [SeatMap.occupancyStats]: total/occupied/ratio computed
/// together in one traversal.
class OccupancyStats {
  const OccupancyStats({
    required this.total,
    required this.occupied,
    required this.ratio,
  });

  final int total;
  final int occupied;
  final double ratio;
}
