import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/models/seat_map.dart';
import '../../../core/theme/app_theme.dart';

/// "Occupati 10/100 · 10%" - a quick read on how full the room is, computed
/// directly from the seat grid we already have rather than trusting the
/// API's own `sessionOccupancy` field, consistent with everything else this
/// screen derives itself.
class OccupancySummary extends StatelessWidget {
  const OccupancySummary({super.key, required this.seatMap});

  final SeatMap seatMap;

  @override
  Widget build(BuildContext context) {
    final total = seatMap.totalSeatCount;
    final occupied = seatMap.occupiedSeatCount;
    final percent = (seatMap.occupancyRatio * 100).round();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${AppLocalizations.of(context).occupiedSummary} $occupied/$total',
          style: AppTheme.mono(
            context,
          ).copyWith(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$percent%',
            style: AppTheme.mono(
              context,
            ).copyWith(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}
