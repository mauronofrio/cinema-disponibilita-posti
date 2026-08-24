import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/models/seat_map.dart';
import '../../../core/theme/app_theme.dart';

/// Categories worth their own legend swatch: only a category with at least
/// one *available* seat, since only an available seat actually renders in
/// its category's own color (see _SeatBox) - a category whose every seat
/// happens to be some other status (e.g. accessibility) never shows that
/// color anywhere in the grid, so listing it would be a legend entry for a
/// swatch nothing on screen matches. Confirmed live: UCI's "SEDIA A
/// ROTELLE" sector at UCI Bicocca Milano has exactly two seats, both also
/// flagged DISABILE, so they always render purple with the wheelchair icon
/// instead of that sector's own light grey - before this filter, the
/// legend still listed a light-grey "SEDIA A ROTELLE" swatch no seat in
/// the room ever actually showed.
List<AreaCategory> visibleAreaCategories(SeatMap seatMap) {
  final availableCategoryCodes = <String>{};
  for (final row in seatMap.rows) {
    for (final seat in row.seats) {
      if (seat != null && seat.status == SeatStatus.available) {
        availableCategoryCodes.add(seat.areaCategoryCode);
      }
    }
  }
  return seatMap.areaCategories
      .where(
        (c) => availableCategoryCodes.contains(c.code) && c.name.isNotEmpty,
      )
      .toList();
}

/// Legend for the pricing/seat-type categories present in this room (colored
/// swatches matching the venue's own `areaColor`, exactly what an available
/// seat is filled with), plus one fixed "Occupato" entry for the single
/// muted grey every non-available seat shares regardless of category.
class AreaLegend extends StatelessWidget {
  const AreaLegend({super.key, required this.seatMap});

  final SeatMap seatMap;

  @override
  Widget build(BuildContext context) {
    var hasGreyOccupiedSeat = false;
    var hasAccessibilitySeat = false;
    for (final row in seatMap.rows) {
      for (final seat in row.seats) {
        if (seat == null) continue;
        switch (seat.status) {
          case SeatStatus.available:
            break;
          case SeatStatus.accessibility:
            hasAccessibilitySeat = true;
          case SeatStatus.occupied:
          case SeatStatus.reserved:
          case SeatStatus.special:
          case SeatStatus.unknown:
            hasGreyOccupiedSeat = true;
        }
      }
    }
    final categories = visibleAreaCategories(seatMap);
    // Chains with real per-category names/colors (The Space, UCI) already
    // convey "this color is available, in this pricing tier" through those
    // entries, so a separate generic one would be redundant. Chains with no
    // such data at all (the 18tickets platform - see PROJECT_NOTES.md, the
    // SVG's own fill is just a placeholder gray, not a real category color)
    // never populate `categories`, so without this fallback there would be
    // no legend entry at all explaining what the plain available color means.
    final hasUncategorizedAvailableSeat =
        categories.isEmpty &&
        seatMap.rows.any(
          (row) => row.seats.any((s) => s?.status == SeatStatus.available),
        );

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final category in categories)
          _LegendEntry(
            color: colorFromHex(category.color) ?? AppColors.seatAvailable,
            label: category.name,
          ),
        if (hasUncategorizedAvailableSeat)
          _LegendEntry(
            color: AppColors.seatAvailable,
            label: AppLocalizations.of(context).seatStatusAvailable,
          ),
        if (hasAccessibilitySeat)
          _LegendEntry(
            color: AppColors.seatAccessibility,
            label: AppLocalizations.of(context).seatStatusAccessibility,
            icon: Icons.accessible,
          ),
        if (hasGreyOccupiedSeat)
          _LegendEntry(
            color: AppColors.seatOccupied,
            label: AppLocalizations.of(context).seatStatusOccupied,
          ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.color, required this.label, this.icon});

  final Color color;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
          child: icon == null
              ? null
              : Icon(icon, size: 9, color: AppColors.background),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTheme.body(
            context,
          ).copyWith(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }
}
