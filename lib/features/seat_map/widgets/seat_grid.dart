import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/models/seat_map.dart';
import '../../../core/theme/app_theme.dart';

/// Flat, shadow-free seat grid: ~500 small `Container`s is cheap to build
/// and paint, so this deliberately skips `GridView.builder`/virtualization
/// in favour of a plain layout, which is simpler to get right for a grid
/// whose size is already known up front (`totalRows` x `totalColumns`, both
/// small).
///
/// Seat size shrinks to fit the available width, so an ordinary room is
/// visible whole at a glance with no side-scrolling. Past a floor
/// ([_minSeatSize]) shrinking stops and the seats scroll sideways instead -
/// below that size the seats stop being individually readable, which
/// defeats the point of showing the whole room. Row labels stay pinned
/// outside the scroll view, so the row you're looking at is always
/// identifiable.
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

  /// How small a seat is allowed to get before the grid starts scrolling
  /// sideways instead of shrinking further.
  ///
  /// Shrinking to fit is still the preferred behaviour - seeing the whole
  /// room at once is the point - but it can't go on forever: with no floor
  /// at all, Orfeo Multisala's 44-column "ROSSA" screen came out at roughly
  /// 4.7px per seat on a normal phone, smaller than the glow drawn around
  /// each free seat, so neighbouring seats smeared into one blur and no
  /// individual seat could be read or tapped for its tooltip.
  ///
  /// 8px is deliberately low, so only genuinely huge rooms scroll: on a
  /// 360dp-wide phone everything up to about 29 columns still fits, which
  /// covers the ordinary 15-26 column rooms across all four chains. Raise
  /// it for bigger seats and more scrolling.
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
        final naturalSize = columns > 0 ? forSeats / columns : _maxSeatSize;
        final seatSize = naturalSize.clamp(_minSeatSize, _maxSeatSize);
        // Below the floor the row genuinely can't fit any more, so the seats
        // area scrolls. The row labels stay pinned outside that scroll view
        // on both sides, so you never lose track of which row you're
        // looking at while panning across a wide room.
        final scrolls = naturalSize < _minSeatSize;

        final seatRows = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in seatMap.rows)
              _SeatRowWidget(row: row, seatMap: seatMap, seatSize: seatSize),
          ],
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ScreenIndicator(width: constraints.maxWidth),
            Row(
              children: [
                _RowLabelColumn(seatMap: seatMap, seatSize: seatSize),
                Expanded(
                  child: scrolls
                      ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: seatRows,
                        )
                      : seatRows,
                ),
                _RowLabelColumn(seatMap: seatMap, seatSize: seatSize),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The row letters running down one side of the grid. Pulled out of the
/// rows themselves so they can sit outside the horizontal scroll view when
/// a wide room scrolls - each entry is pinned to the same height as its
/// row so the two columns stay aligned.
class _RowLabelColumn extends StatelessWidget {
  const _RowLabelColumn({required this.seatMap, required this.seatSize});

  final SeatMap seatMap;
  final double seatSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in seatMap.rows)
          SizedBox(
            width: SeatGrid._rowLabelWidth,
            height: seatSize + SeatGrid._gap,
            child: Center(
              child: Text(
                row.rowLabel,
                textAlign: TextAlign.center,
                style: AppTheme.mono(
                  context,
                ).copyWith(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
          ),
      ],
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
            AppLocalizations.of(context).screenIndicator,
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

  /// Just the seats - the row's own label lives in [_RowLabelColumn],
  /// outside any horizontal scroll view, so it stays visible while a wide
  /// room is panned sideways.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SeatGrid._gap / 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
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
                      category: seatMap.categoryFor(seat.areaCategoryCode),
                      size: seatSize,
                    ),
            ),
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
    final isAccessibility = seat.status == SeatStatus.accessibility;
    // Available: filled with the seat's own category color (VIP/Standard/...
    // as defined by the venue itself), so category reads at a glance right
    // where it's actionable. Accessibility gets its own fixed color for the
    // same reason (see AppColors.seatAccessibility). Everything else
    // collapses to one muted grey - its category no longer matters since it
    // can't be picked anyway.
    final color = isAvailable
        ? (colorFromHex(category?.color) ?? AppColors.seatAvailable)
        : isAccessibility
        ? AppColors.seatAccessibility
        : AppColors.seatOccupied;
    final standsOut = isAvailable || isAccessibility;
    final categoryName = category?.name;
    final label = [
      seat.name,
      labelForSeatStatus(seat.status, context),
      if (categoryName?.isNotEmpty ?? false) categoryName!,
    ].join(' · ');
    return Semantics(
      // Seats are read-only in this app - purely informational, never
      // tappable - so this is deliberately not `button: true`.
      label: label,
      enabled: false,
      child: Tooltip(
        message: label,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(size * 0.22),
            border: standsOut ? null : Border.all(color: AppColors.hairline),
            boxShadow: standsOut
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.55),
                      blurRadius: 6,
                      spreadRadius: 0.5,
                    ),
                  ]
                : null,
          ),
          child: isAccessibility
              ? Icon(
                  Icons.accessible,
                  size: size * 0.7,
                  color: AppColors.background,
                )
              : null,
        ),
      ),
    );
  }
}
