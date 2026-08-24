import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/date/clock.dart';
import '../../core/date/day_label.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/models/cinema.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/film_perforation_divider.dart';
import '../../core/update/update_checker.dart';
import '../../core/update/update_dialog.dart';
import '../cinema_picker/cinema_list_provider.dart';
import 'films_provider.dart';
import 'showing_dates_provider.dart';
import 'widgets/day_selector.dart';
import 'widgets/film_card.dart';

class ShowtimesHomeScreen extends ConsumerStatefulWidget {
  const ShowtimesHomeScreen({super.key});

  @override
  ConsumerState<ShowtimesHomeScreen> createState() =>
      _ShowtimesHomeScreenState();
}

class _ShowtimesHomeScreenState extends ConsumerState<ShowtimesHomeScreen> {
  DateTime? _selectedDay;

  /// Which cinema [_selectedDay] was picked for - switching cinema (e.g.
  /// from settings) should land back on today's programme, not whichever
  /// day happened to be selected for the previous cinema.
  Cinema? _selectedDayCinema;

  @override
  Widget build(BuildContext context) {
    final activeAsync = ref.watch(activeCinemaProvider);
    final t = AppLocalizations.of(context);

    return Scaffold(
      body: activeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('${t.genericError} $err')),
        data: (cinema) {
          if (cinema == null) {
            // No active cinema yet - redirect handled by the router; this
            // frame just avoids flashing an empty screen.
            return const SizedBox.shrink();
          }
          if (_selectedDayCinema != cinema) {
            _selectedDayCinema = cinema;
            _selectedDay = null;
          }
          return _CinemaShowtimes(
            cinema: cinema,
            selectedDay: _selectedDay,
            onSelectDay: (d) => setState(() => _selectedDay = d),
          );
        },
      ),
    );
  }
}

class _CinemaShowtimes extends ConsumerWidget {
  const _CinemaShowtimes({
    required this.cinema,
    required this.selectedDay,
    required this.onSelectDay,
  });

  final Cinema cinema;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onSelectDay;

  /// Confirms first - an accidental tap on this icon (easy to brush against,
  /// right next to the settings icon) would otherwise jump straight out to
  /// Google Maps with no way back except re-navigating.
  Future<void> _confirmAndOpenDirections(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.openMapsTitle),
        content: Text(t.openMapsMessage(cinema.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.open),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await launchUrl(
        Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=${cinema.lat},${cinema.lng}',
        ),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daysAsync = ref.watch(showingDatesProvider(cinema));
    final now = ref.watch(clockProvider).now();
    final t = AppLocalizations.of(context);
    // The on-start prompt (see _UpdateCheckGate in app.dart) only ever shows
    // once per app session - dismissing it with "Later" would otherwise
    // leave no way back to it short of restarting the app. Reading the
    // same cached provider here costs nothing extra (already resolved by
    // the time this screen is up) and gives that a permanent way back in.
    final availableUpdate = ref.watch(updateCheckProvider).value;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          // Flutter has no true "wrap content" toolbar height - this is a
          // fixed value tuned to sit just above the title text's own line
          // height plus the 4px top/bottom padding below, not a real
          // intrinsic measurement.
          toolbarHeight: 40,
          title: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                cinema.displayName,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
          pinned: true,
          actions: [
            if (availableUpdate != null)
              IconButton(
                icon: const Icon(Icons.system_update),
                tooltip: t.updateAvailableTitle,
                onPressed: () => showUpdateDialog(context, availableUpdate),
              ),
            IconButton(
              icon: const Icon(Icons.directions),
              tooltip: t.getDirections,
              onPressed: () => _confirmAndOpenDirections(context),
            ),
            IconButton(
              icon: const Icon(Icons.tune),
              onPressed: () => context.push('/settings'),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: daysAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${t.daysLoadError} $err'),
            ),
            data: (days) {
              final available = days.where((d) => d.hasShowings).toList();
              if (available.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    t.noShowingsAvailable,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                );
              }
              // Re-derived every build against the *current* available days,
              // not just defaulted once and cached - otherwise a day picked
              // (explicitly or by auto-default) before a midnight rollover
              // stays selected forever even once it's aged out of the fresh
              // list, forcing a stale date until the user manually reselects.
              final effectiveSelected = pickSelectedDay(
                selectedDay,
                available.map((d) => d.date).toList(),
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (effectiveSelected != selectedDay) {
                  onSelectDay(effectiveSelected);
                }
              });
              return Column(
                children: [
                  DaySelector(
                    days: days,
                    selected: effectiveSelected,
                    now: now,
                    onSelect: onSelectDay,
                  ),
                  const FilmPerforationDivider(),
                ],
              );
            },
          ),
        ),
        if (selectedDay != null)
          ref
              .watch(filmsForDayProvider((cinema, selectedDay!)))
              .when(
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (err, _) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('${t.filmsLoadError} $err'),
                  ),
                ),
                data: (films) {
                  final day = selectedDay!;
                  final filmsToday = films
                      .where((f) => f.sessionsOn(day).isNotEmpty)
                      .toList();
                  if (filmsToday.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          t.noFilmsForDay,
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    );
                  }
                  return SliverList.separated(
                    itemCount: filmsToday.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final film = filmsToday[index];
                      return Padding(
                        // Only the top gets extra space for the first card (a
                        // little breathing room under the day chips) - giving
                        // it bottom padding too would make the 1st-to-2nd gap
                        // bigger than every other gap between cards.
                        padding: EdgeInsets.fromLTRB(
                          16,
                          index == 0 ? 12 : 0,
                          16,
                          0,
                        ),
                        child: FilmCard(
                          film: film,
                          cinema: cinema,
                          sessions: film.sessionsOn(day),
                        ),
                      );
                    },
                  );
                },
              ),
        SliverPadding(
          // See seat_map_screen.dart: edge-to-edge system nav bar floats
          // over the content, so its inset must be added explicitly.
          padding: EdgeInsets.only(
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
          ),
        ),
      ],
    );
  }
}
