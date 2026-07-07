import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/date/clock.dart';
import '../../../core/models/cinema.dart';
import '../../../core/models/film.dart';
import '../../../core/theme/app_theme.dart';
import '../../seat_map/seat_map_provider.dart';

class FilmCard extends ConsumerWidget {
  const FilmCard({
    super.key,
    required this.film,
    required this.cinema,
    required this.sessions,
  });

  final Film film;
  final Cinema cinema;
  final List<Session> sessions;

  void _openSeatMap(BuildContext context, WidgetRef ref, Session session) {
    // Fire off the seat-map fetch immediately, before the navigation
    // transition even starts, so it's often already resolved by the time
    // the seat map screen's own `ref.watch` runs.
    ref
        .read(seatMapProvider((cinema.cinemaId, session.sessionId)).future)
        .ignore();
    context.push(
      '/seat-map',
      extra: SeatMapArgs(
        cinemaId: cinema.cinemaId,
        filmTitle: film.title,
        showingGroups: film.showingGroups,
        initialSessionId: session.sessionId,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).now();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: film.posterImageSrc == null
                  ? Container(
                      width: 64,
                      height: 96,
                      color: AppColors.surfaceElevated,
                    )
                  : Image.network(
                      film.posterImageSrc!,
                      width: 64,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 64,
                        height: 96,
                        color: AppColors.surfaceElevated,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    film.title,
                    style: AppTheme.display(
                      context,
                    ).copyWith(fontSize: 20, height: 1),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (film.runningTime != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${film.runningTime} min',
                      style: AppTheme.body(
                        context,
                      ).copyWith(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: sessions.map((session) {
                      return _SessionTimeChip(
                        session: session,
                        isPast: now.isAfter(session.startTime),
                        onTap: () => _openSeatMap(context, ref, session),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTimeChip extends StatelessWidget {
  const _SessionTimeChip({
    required this.session,
    required this.isPast,
    required this.onTap,
  });

  final Session session;
  final bool isPast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final soldOut = session.isSoldOut;
    // Once a showtime has started, the seats endpoint stops returning
    // availability for it - so the time is kept visible (still useful as a
    // record of the day's programme) but is no longer tappable, distinct
    // from "sold out" which is a different, still-relevant state.
    final disabled = soldOut || isPast;
    return Material(
      color: disabled ? AppColors.surfaceElevated : AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.hairline),
      ),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            soldOut
                ? '${DateFormat.Hm().format(session.startTime)} · esaurito'
                : DateFormat.Hm().format(session.startTime),
            style: AppTheme.mono(context).copyWith(
              fontSize: 13,
              color: disabled ? AppColors.textMuted : AppColors.textPrimary,
              decoration: soldOut ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ),
    );
  }
}
