import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date/clock.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/models/film.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/error_with_retry.dart';
import '../film_info/film_info_sheet.dart';
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
/// `showingGroups` already covers every day in one response. For
/// 18tickets-platform cinemas (RedCarpet, Multicinema Galleria, ...) it's
/// only free for the one day the user came from; picking any other day this
/// cinema has showings for (from [showingDatesProvider], already cached
/// from the home screen) fetches just that one day lazily via
/// [filmsForDayProvider] and merges it in - see PROJECT_NOTES.md for why
/// this platform can't just fetch every day up front the way the other two
/// do.
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

  /// [dates] plus the currently-shown day if it isn't already there, in
  /// chronological order - see the call site for why the selected day is
  /// added to the list rather than the selection being moved into it.
  List<DateTime> _withSelectedDate(List<DateTime> dates) {
    final selectedKey = _dayKey(_selectedDate);
    if (dates.any((d) => _dayKey(d) == selectedKey)) return dates;
    return [...dates, _selectedDate]..sort();
  }

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
      // Same emptiness guard the fetched path below already applies before
      // storing a group. `ShowingGroup.fromJson` tolerates `sessions: []`,
      // so a dated-but-empty group can reach here from the nav args too -
      // and `_applyGroup`'s `orElse: () => group.sessions.first` would then
      // throw a StateError inside setState, i.e. a red screen.
      if (known.sessions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).noShowingsForFilmThatDay,
            ),
          ),
        );
        return;
      }
      _applyGroup(known, date);
      return;
    }

    // Not already known (18tickets-platform cinemas only - see class doc):
    // fetch just this one day, find the same film in it by id, and merge
    // its sessions in.
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
    final now = ref.watch(clockProvider).now();

    return Scaffold(
      appBar: AppBar(
        // Same reasoning as ShowtimesHomeScreen's SliverAppBar: no true
        // "wrap content" toolbar height in Flutter, so this is a fixed
        // value tuned to sit just above the title text's own line height
        // plus the 4px top/bottom padding below, not a real intrinsic
        // measurement.
        toolbarHeight: 40,
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(widget.args.filmTitle, maxLines: 1, softWrap: false),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: AppLocalizations.of(context).filmInfoTooltip,
            onPressed: () => showFilmInfoSheet(
              context,
              FilmInfoArgs(
                title: widget.args.filmTitle,
                posterImageSrc: widget.args.posterImageSrc,
                runningTime: widget.args.runningTime,
              ),
            ),
          ),
        ],
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
            // Its own Consumer: only this chip strip needs to rebuild when
            // `showingDatesProvider` resolves/changes, not the seat grid
            // below it.
            Consumer(
              builder: (context, ref, _) {
                // Same cached provider the home screen already populated -
                // for The Space/UCI this is a strict superset of
                // `_groupsByDay`'s keys anyway (both come from the same
                // one-shot fetch), for 18tickets-platform cinemas it's the
                // whole cinema's calendar even though only one of its days
                // has this film's sessions loaded yet. Falls back to what's
                // already known from the nav args if this hasn't resolved
                // yet, so the switcher never shows fewer days than it did a
                // moment ago on the home screen.
                final liveDates = ref
                    .watch(showingDatesProvider(widget.args.cinema))
                    .maybeWhen(
                      data: (days) => days
                          .where((d) => d.hasShowings)
                          .map((d) => d.date)
                          .toList(),
                      orElse: () =>
                          widget.args.showingGroups.map((g) => g.date).toList(),
                    );
                // The live list can drift from what this screen is actually
                // showing (day rollover, background refetch), and when it
                // no longer contains `_selectedDate` the switcher finds no
                // match: no chip renders selected and the strip silently
                // scrolls back to the start while the grid below keeps
                // showing the old day's session. Deliberately NOT solved by
                // re-deriving `_selectedDate` the way the home screen does
                // with `pickSelectedDay` - there the selection is just a
                // filter, here it's bound to the sessions already loaded
                // into `_groupsByDay`, so silently moving it would leave
                // `_selectedGroup` pointing at a day that was never fetched.
                // Instead the currently-shown day is always kept in the
                // list, so the highlight always matches the grid.
                final availableDates = _withSelectedDate(liveDates);
                return DateSwitcher(
                  availableDates: availableDates,
                  selectedDate: _selectedDate,
                  now: now,
                  onSelect: _selectDate,
                  loadingDate: _loadingDate,
                );
              },
            ),
            const SizedBox(height: 2),
            TimeSwitcher(
              sessions: _selectedGroup.sessions,
              selectedSessionId: _selectedSessionId,
              now: now,
              onSelect: _selectSession,
            ),
            const SizedBox(height: 8),
            // Its own Consumer: only the occupancy count/grid/buy button
            // need to rebuild on every `seatMapProvider` refetch (its short
            // TTL means this can happen often), not the switchers above.
            Consumer(
              builder: (context, ref, _) {
                final seatMapAsync = ref.watch(seatMapProvider(key));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.theaters_outlined,
                              size: 14,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              session.screenName,
                              style: AppTheme.mono(context).copyWith(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
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
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: ErrorWithRetry(
                          message:
                              '${AppLocalizations.of(context).seatsLoadError}\n$err',
                          onRetry: () => ref.invalidate(seatMapProvider(key)),
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
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
