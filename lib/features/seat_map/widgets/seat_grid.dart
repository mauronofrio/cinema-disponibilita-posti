import 'package:flutter/material.dart';

import '../../../core/models/seat_map.dart';
import '../../../core/theme/app_theme.dart';

/// Flat, shadow-free seat grid: ~500 small `Container`s is cheap to build
/// and paint, so this deliberately skips `GridView.builder`/virtualization
/// in favour of a plain layout, which is simpler to get right for a grid
/// whose size is already known up front (`totalRows` x `totalColumns`, both
/// small).
///
/// The grid always fits the available width - seat size shrinks to fit
/// rather than the row scrolling horizontally, so the whole room is visible
/// at a glance without side-scrolling any individual row.
///
/// Available seats are filled with their own pricing/seat-type category
/// color (Standard, VIP, ... - the venue's own `areaColor`), so category is
/// visible at a glance exactly where it matters; anything not available
/// collapses to a single muted grey, since its category is no longer
/// actionable. This mirrors the reference implementation's own seat map
/// rendering (github.com/mauronofrio/TheSpace_Fast_Seat_Check).
class SeatGrid extends StatelessWidget {
  const SeatGrid({super.key, required this.seatMap});

  final SeatMap seatMap;

  static const _maxSeatSize = 22.0;
  static const _minSeatSize = 8.0;
  static const _gap = 2.0;
  static const _rowLabelWidth = 16.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = seatMap.totalColumns;
        final forSeats =
            constraints.maxWidth - _rowLabelWidth * 2 - _gap * (columns + 1);
        final seatSize = columns > 0
            ? (forSeats / columns).clamp(_minSeatSize, _maxSeatSize)
            : _maxSeatSize;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ScreenIndicator(width: constraints.maxWidth),
            for (final row in seatMap.rows)
              _SeatRowWidget(row: row, seatMap: seatMap, seatSize: seatSize),
          ],
        );
      },
    );
  }
}

/// A shallow glowing arc labelled "SCHERMO" so the grid below it reads
/// unambiguously as "screen at the top, seats facing it" - the same
/// orientation cue every real seat map shows.
class _ScreenIndicator extends StatelessWidget {
  const _ScreenIndicator({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          CustomPaint(
            size: Size(width, 16),
            painter: const _ScreenArcPainter(),
          ),
          const SizedBox(height: 8),
          Text(
            'SCHERMO',
            style: AppTheme.mono(context).copyWith(
              fontSize: 11,
              letterSpacing: 4,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenArcPainter extends CustomPainter {
  const _ScreenArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(size.width / 2, 0, size.width, size.height);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = AppColors.marquee.withValues(alpha: 0.75)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ScreenArcPainter oldDelegate) => false;
}

class _SeatRowWidget extends StatelessWidget {
  const _SeatRowWidget({
    required this.row,
    required this.seatMap,
    required this.seatSize,
  });

  final SeatRow row;
  final SeatMap seatMap;
  final double seatSize;

  Widget _rowLabel(BuildContext context) {
    return SizedBox(
      width: SeatGrid._rowLabelWidth,
      child: Text(
        row.rowLabel,
        textAlign: TextAlign.center,
        style: AppTheme.mono(
          context,
        ).copyWith(fontSize: 11, color: AppColors.textMuted),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SeatGrid._gap / 2),
      child: Row(
        children: [
          _rowLabel(context),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final seat in row.seats)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SeatGrid._gap / 2,
                    ),
                    child: seat == null
                        ? SizedBox(width: seatSize, height: seatSize)
                        : _SeatBox(
                            seat: seat,
                            category: seatMap.categoryFor(
                              seat.areaCategoryCode,
                            ),
                            size: seatSize,
                          ),
                  ),
              ],
            ),
          ),
          _rowLabel(context),
        ],
      ),
    );
  }
}

class _SeatBox extends StatelessWidget {
  const _SeatBox({
    required this.seat,
    required this.category,
    required this.size,
  });

  final Seat seat;
  final AreaCategory? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isAvailable = seat.status == SeatStatus.available;
    // Available: filled with the seat's own category color (VIP/Standard/...
    // as defined by the venue itself), so category reads at a glance right
    // where it's actionable. Anything else collapses to one muted grey - its
    // category no longer matters since it can't be picked anyway.
    final color = isAvailable
        ? (colorFromHex(category?.color) ?? AppColors.seatAvailable)
        : AppColors.seatOccupied;
    final categoryName = category?.name;
    return Tooltip(
      message: [
        seat.name,
        labelForSeatStatus(seat.status),
        if (categoryName?.isNotEmpty ?? false) categoryName!,
      ].join(' · '),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size * 0.22),
          border: isAvailable ? null : Border.all(color: AppColors.hairline),
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
