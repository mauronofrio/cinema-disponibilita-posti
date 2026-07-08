import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date/clock.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/models/film.dart';
import '../../core/theme/app_theme.dart';
import '../showtimes/films_provider.dart';
import '../showtimes/showing_dates_provider.dart';
import 'seat_map_provider.dart';
import 'widgets/area_legend.dart';
import 'widgets/buy_tickets_button.dart';
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
/// here via [DateSwitcher]/[TimeSwitcher] instead of forcing a trip back to
/// the film list. For The Space/UCI this is always free - their own
/// `showingGroups` already covers every day in one response. For RedCarpet
/// it's only free for the one day the user came from; picking any other
/// day this cinema has showings for (from [showingDatesProvider], already
/// cached from the home screen) fetches just that one day lazily via
/// [filmsForDayProvider] and merges it in - see PROJECT_NOTES.md for why
/// RedCarpet can't just fetch every day up front the way the other two do.
class SeatMapScreen extends ConsumerStatefulWidget {
  const SeatMapScreen({super.key, required this.args});

  final SeatMapArgs args;

  @override
  ConsumerState<SeatMapScreen> createState() => _SeatMapScreenState();
}

class _SeatMapScreenState extends ConsumerState<SeatMapScreen> {
  late final Map<DateTime, ShowingGroup> _groupsByDay = {
    for (final g in widget.args.showingGroups) _dayKey(g.date): g,
  };
  late String _selectedSessionId = widget.args.initialSessionId;
  late DateTime _selectedDate = widget.args.showingGroups
      .firstWhere(
        (g) => g.sessions.any((s) => s.sessionId == _selectedSessionId),
      )
      .date;
  DateTime? _loadingDate;

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  ShowingGroup get _selectedGroup => _groupsByDay[_dayKey(_selectedDate)]!;

  Session get _selectedSession => _selectedGroup.sessions.firstWhere(
    (s) => s.sessionId == _selectedSessionId,
  );

  void _applyGroup(ShowingGroup group, DateTime date) {
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

  Future<void> _selectDate(DateTime date) async {
    final key = _dayKey(date);
    final known = _groupsByDay[key];
    if (known != null) {
      _applyGroup(known, date);
      return;
    }

    // Not already known (RedCarpet only - see class doc): fetch just this
    // one day, find the same film in it by id, and merge its sessions in.
    setState(() => _loadingDate = date);
    ShowingGroup? fetchedGroup;
    var failed = false;
    try {
      final films = await ref.read(
        filmsForDayProvider((widget.args.cinema, date)).future,
      );
      for (final film in films) {
        if (film.filmId != widget.args.filmId) continue;
        for (final group in film.showingGroups) {
          if (_dayKey(group.date) == key && group.sessions.isNotEmpty) {
            fetchedGroup = group;
          }
        }
      }
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() => _loadingDate = null);

    if (fetchedGroup != null) {
      _groupsByDay[key] = fetchedGroup;
      _applyGroup(fetchedGroup, date);
    } else {
      final t = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failed ? t.seatsLoadError : t.noShowingsForFilmThatDay),
        ),
      );
    }
  }

  void _selectSession(Session session, {DateTime? date}) {
    // Fire off the seat-map fetch immediately, before the chip even finishes
    // its selected-state animation, so it's often already resolved by the
    // time the rest of the screen rebuilds around it.
    ref.read(seatMapProvider((widget.args.cinema, session)).future).ignore();
    setState(() {
      _selectedSessionId = session.sessionId;
      if (date != null) _selectedDate = date;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _selectedSession;
    final key = (widget.args.cinema, session);
    final seatMapAsync = ref.watch(seatMapProvider(key));
    final now = ref.watch(clockProvider).now();
    // Same cached provider the home screen already populated - for The
    // Space/UCI this is a strict superset of `_groupsByDay`'s keys anyway
    // (both come from the same one-shot fetch), for RedCarpet it's the
    // whole cinema's calendar even though only one of its days has this
    // film's sessions loaded yet. Falls back to what's already known from
    // the nav args if this hasn't resolved yet, so the switcher never shows
    // fewer days than it did a moment ago on the home screen.
    final availableDates = ref
        .watch(showingDatesProvider(widget.args.cinema))
        .maybeWhen(
          data: (days) =>
              days.where((d) => d.hasShowings).map((d) => d.date).toList(),
          orElse: () => widget.args.showingGroups.map((g) => g.date).toList(),
        );

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
            4,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            DateSwitcher(
              availableDates: availableDates,
              selectedDate: _selectedDate,
              now: now,
              onSelect: _selectDate,
              loadingDate: _loadingDate,
            ),
            const SizedBox(height: 2),
            TimeSwitcher(
              sessions: _selectedGroup.sessions,
              selectedSessionId: _selectedSessionId,
              now: now,
              onSelect: _selectSession,
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 12),
            seatMapAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    '${AppLocalizations.of(context).seatsLoadError}\n$err',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (seatMap) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AreaLegend(seatMap: seatMap),
                    const SizedBox(height: 12),
                    SeatGrid(seatMap: seatMap),
                    const SizedBox(height: 32),
                    BuyTicketsButton(session: session),
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
