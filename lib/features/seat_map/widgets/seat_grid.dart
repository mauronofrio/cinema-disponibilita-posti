import 'package:flutter/material.dart';

import '../../../core/models/seat_map.dart';
import '../../../core/theme/app_theme.dart';

/// Flat, shadow-free seat grid: ~500 small `Container`s is cheap to build
/// and paint, so this deliberately skips `GridView.builder`/virtualization
/// in favour of a plain nested-scroll layout, which is simpler to get right
/// for a grid whose size is already known up front (`totalRows` x
/// `totalColumns`, both small).
class SeatGrid extends StatelessWidget {
  const SeatGrid({super.key, required this.seatMap});

  final SeatMap seatMap;

  static const _seatSize = 22.0;
  static const _gap = 3.0;
  static const _rowLabelWidth = 22.0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final row in seatMap.rows) _SeatRowWidget(row: row)],
        ),
      ),
    );
  }
}

class _SeatRowWidget extends StatelessWidget {
  const _SeatRowWidget({required this.row});

  final SeatRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SeatGrid._gap / 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: SeatGrid._rowLabelWidth,
            child: Text(
              row.rowLabel,
              textAlign: TextAlign.center,
              style: AppTheme.mono(
                context,
              ).copyWith(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
          for (final seat in row.seats)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SeatGrid._gap / 2,
              ),
              child: seat == null
                  ? const SizedBox(
                      width: SeatGrid._seatSize,
                      height: SeatGrid._seatSize,
                    )
                  : _SeatBox(seat: seat),
            ),
        ],
      ),
    );
  }
}

class _SeatBox extends StatelessWidget {
  const _SeatBox({required this.seat});

  final Seat seat;

  @override
  Widget build(BuildContext context) {
    final color = colorForSeatStatus(seat.status);
    final isAvailable = seat.status == SeatStatus.available;
    return Tooltip(
      message: '${seat.name} · ${labelForSeatStatus(seat.status)}',
      child: Container(
        width: SeatGrid._seatSize,
        height: SeatGrid._seatSize,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
          boxShadow: isAvailable
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.55),
                    blurRadius: 6,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}
