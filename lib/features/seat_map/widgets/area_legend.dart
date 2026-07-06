import 'package:flutter/material.dart';

import '../../../core/models/seat_map.dart';
import '../../../core/theme/app_theme.dart';

/// Legend for the statuses actually present in this room - no point showing
/// "Accessibilità" or "Speciale" swatches for a screen that has none.
class AreaLegend extends StatelessWidget {
  const AreaLegend({super.key, required this.seatMap});

  final SeatMap seatMap;

  @override
  Widget build(BuildContext context) {
    final present = <SeatStatus>{};
    for (final row in seatMap.rows) {
      for (final seat in row.seats) {
        if (seat != null) present.add(seat.status);
      }
    }
    const order = [
      SeatStatus.available,
      SeatStatus.occupied,
      SeatStatus.reserved,
      SeatStatus.special,
      SeatStatus.accessibility,
    ];

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final status in order)
          if (present.contains(status))
            _LegendEntry(
              color: colorForSeatStatus(status),
              label: labelForSeatStatus(status),
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
