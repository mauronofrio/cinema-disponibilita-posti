import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/models/seat_map.dart';
import '../../../core/theme/app_theme.dart';

/// Legend for the pricing/seat-type categories present in this room (colored
/// swatches matching the venue's own `areaColor`, exactly what an available
/// seat is filled with), plus one fixed "Occupato" entry for the single
/// muted grey every non-available seat shares regardless of category.
class AreaLegend extends StatelessWidget {
  const AreaLegend({super.key, required this.seatMap});

  final SeatMap seatMap;

  @override
  Widget build(BuildContext context) {
    final presentCategoryCodes = <String>{};
    var hasUnavailableSeat = false;
    for (final row in seatMap.rows) {
      for (final seat in row.seats) {
        if (seat == null) continue;
        presentCategoryCodes.add(seat.areaCategoryCode);
        if (seat.status != SeatStatus.available) hasUnavailableSeat = true;
      }
    }
    final categories = seatMap.areaCategories
        .where(
          (c) => presentCategoryCodes.contains(c.code) && c.name.isNotEmpty,
        )
        .toList();

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final category in categories)
          _LegendEntry(
            color: colorFromHex(category.color) ?? AppColors.seatAvailable,
            label: category.name,
          ),
        if (hasUnavailableSeat)
          _LegendEntry(
            color: AppColors.seatOccupied,
            label: AppLocalizations.of(context).seatStatusOccupied,
          ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.color, required this.label});

  final Color color;
  final String label;

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
