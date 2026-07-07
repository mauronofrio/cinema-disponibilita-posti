import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date/clock.dart';
import '../../core/models/film.dart';
import '../../core/theme/app_theme.dart';
import 'seat_map_provider.dart';
import 'widgets/area_legend.dart';
import 'widgets/date_switcher.dart';
import 'widgets/occupancy_summary.dart';
import 'widgets/seat_grid.dart';
import 'widgets/time_switcher.dart';

/// Read-only seat map: no seat is tappable/selectable, there is no checkout.
/// The entire point is "can I see, at a glance, what's free" - so loading
/// calls only the seats endpoint directly (see [TheSpaceApiClient.getSeatMapJson]),
/// skipping the order/payment/concessions flow the official app/website
/// trigger unnecessarily on the same tap.
///
/// Switching to another day or showtime of the same film happens right
/// here via [DateSwitcher]/[TimeSwitcher], instead of forcing a trip back
/// to the film list - both are free since `showingGroups` already covers
/// every day in the one response the film list itself loaded.
class SeatMapScreen extends ConsumerStatefulWidget {
  const SeatMapScreen({super.key, required this.args});

  final SeatMapArgs args;

  @override
  ConsumerState<SeatMapScreen> createState() => _SeatMapScreenState();
}

class _SeatMapScreenState extends ConsumerState<SeatMapScreen> {
  late String _selectedSessionId = widget.args.initialSessionId;
  late DateTime _selectedDate = widget.args.showingGroups
      .firstWhere(
        (g) => g.sessions.any((s) => s.sessionId == _selectedSessionId),
      )
      .date;

  ShowingGroup get _selectedGroup => widget.args.showingGroups.firstWhere(
    (g) =>
        g.date.year == _selectedDate.year &&
        g.date.month == _selectedDate.month &&
        g.date.day == _selectedDate.day,
  );

  Session get _selectedSession => _selectedGroup.sessions.firstWhere(
    (s) => s.sessionId == _selectedSessionId,
  );

  void _selectDate(DateTime date) {
    final group = widget.args.showingGroups.firstWhere(
      (g) =>
          g.date.year == date.year &&
          g.date.month == date.month &&
          g.date.day == date.day,
    );
    final now = ref.read(clockProvider).now();
    // Default to the first showtime that hasn't started/sold out yet,
    // rather than always landing on the day's first (possibly already
    // past) session.
    final defaultSession = group.sessions.firstWhere(
      (s) => !s.isSoldOut && now.isBefore(s.startTime),
      orElse: () => group.sessions.first,
    );
    _selectSession(defaultSession, date: date);
  }

  void _selectSession(Session session, {DateTime? date}) {
    // Fire off the seat-map fetch immediately, before the chip even finishes
    // its selected-state animation, so it's often already resolved by the
    // time the rest of the screen rebuilds around it.
    ref
        .read(seatMapProvider((widget.args.cinemaId, session.sessionId)).future)
        .ignore();
    setState(() {
      _selectedSessionId = session.sessionId;
      if (date != null) _selectedDate = date;
    });
  }

  @override
  Widget build(BuildContext context) {
    final key = (widget.args.cinemaId, _selectedSessionId);
    final seatMapAsync = ref.watch(seatMapProvider(key));
    final now = ref.watch(clockProvider).now();
    final session = _selectedSession;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.args.filmTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(seatMapProvider(key));
          await ref.read(seatMapProvider(key).future);
        },
        child: ListView(
          // Android 15+ edge-to-edge means the system nav bar floats over the
          // app rather than reserving its own space, so the bottom inset has
          // to be added explicitly or the last rows of the grid end up
          // permanently hidden behind it.
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            DateSwitcher(
              showingGroups: widget.args.showingGroups,
              selectedDate: _selectedDate,
              now: now,
              onSelect: _selectDate,
            ),
            const SizedBox(height: 8),
            TimeSwitcher(
              sessions: _selectedGroup.sessions,
              selectedSessionId: _selectedSessionId,
              now: now,
              onSelect: _selectSession,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  session.screenName,
                  style: AppTheme.mono(
                    context,
                  ).copyWith(fontSize: 13, color: AppColors.textMuted),
                ),
                seatMapAsync.maybeWhen(
                  data: (m) => OccupancySummary(seatMap: m),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            seatMapAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    'Impossibile caricare i posti.\n$err',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (seatMap) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AreaLegend(seatMap: seatMap),
                    const SizedBox(height: 20),
                    SeatGrid(seatMap: seatMap),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
