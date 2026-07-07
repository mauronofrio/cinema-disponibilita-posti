import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/date/clock.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/models/cinema.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/film_perforation_divider.dart';
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
    final filmsAsync = ref.watch(filmsForCinemaProvider(cinema));
    final now = ref.watch(clockProvider).now();
    final t = AppLocalizations.of(context);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: Text(cinema.displayName),
          pinned: true,
          actions: [
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
              final effectiveSelected = selectedDay ?? available.first.date;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (selectedDay == null) onSelectDay(effectiveSelected);
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
          filmsAsync.when(
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
