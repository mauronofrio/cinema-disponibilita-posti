import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/date/clock.dart';
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
    final favoriteAsync = ref.watch(favoriteCinemaProvider);

    return Scaffold(
      body: favoriteAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Errore: $err')),
        data: (cinema) {
          if (cinema == null) {
            // No favorite saved yet - redirect handled by the router; this
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daysAsync = ref.watch(showingDatesProvider(cinema.cinemaId));
    final filmsAsync = ref.watch(filmsForCinemaProvider(cinema.cinemaId));
    final now = ref.watch(clockProvider).now();

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: Text(cinema.name),
          pinned: true,
          actions: [
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
              child: Text('Errore giorni: $err'),
            ),
            data: (days) {
              final available = days.where((d) => d.hasShowings).toList();
              if (available.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Nessuno spettacolo disponibile.',
                    style: TextStyle(color: AppColors.textMuted),
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
                child: Text('Errore film: $err'),
              ),
            ),
            data: (films) {
              final day = selectedDay!;
              final filmsToday = films
                  .where((f) => f.sessionsOn(day).isNotEmpty)
                  .toList();
              if (filmsToday.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Nessun film in programmazione per questo giorno.',
                      style: TextStyle(color: AppColors.textMuted),
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
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: index == 0 ? 12 : 0,
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
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}
