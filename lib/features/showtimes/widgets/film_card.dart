import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/date/clock.dart';
import '../../../core/localization/app_localizations.dart';
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
    ref.read(seatMapProvider((cinema, session)).future).ignore();
    context.push(
      '/seat-map',
      extra: SeatMapArgs(
        cinema: cinema,
        filmId: film.filmId,
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
                  _SessionsByLanguage(
                    sessions: sessions,
                    now: now,
                    canOpenSeatMap: cinema.hasSeatMap,
                    onTapSession: (session) =>
                        _openSeatMap(context, ref, session),
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

/// Splits [sessions] into one labeled row per `Language` value (see
/// [groupSessionsByLanguage]) - but only when there's actually more than one
/// to distinguish, so the common single-language case renders identically
/// to a single unlabeled [Wrap] of chips, same as before this split existed.
class _SessionsByLanguage extends StatelessWidget {
  const _SessionsByLanguage({
    required this.sessions,
    required this.now,
    required this.canOpenSeatMap,
    required this.onTapSession,
  });

  final List<Session> sessions;
  final DateTime now;
  final bool canOpenSeatMap;
  final ValueChanged<Session> onTapSession;

  @override
  Widget build(BuildContext context) {
    final groups = groupSessionsByLanguage(sessions);
    final showLabels = groups.length > 1;

    Widget chipsFor(List<Session> groupSessions) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: groupSessions.map((session) {
        return _SessionTimeChip(
          session: session,
          isPast: now.isAfter(session.startTime),
          canOpenSeatMap: canOpenSeatMap,
          onTap: () => onTapSession(session),
        );
      }).toList(),
    );

    if (!showLabels) return chipsFor(sessions);

    final entries = groups.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          if (entries[i].key != null) ...[
            Text(
              entries[i].key!,
              style: AppTheme.mono(context).copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
          ],
          chipsFor(entries[i].value),
        ],
      ],
    );
  }
}

class _SessionTimeChip extends StatelessWidget {
  const _SessionTimeChip({
    required this.session,
    required this.isPast,
    required this.canOpenSeatMap,
    required this.onTap,
  });

  final Session session;
  final bool isPast;
  final bool canOpenSeatMap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final soldOut = session.isSoldOut;
    // Once a showtime has started, the seats endpoint stops returning
    // availability for it - so the time is kept visible (still useful as a
    // record of the day's programme) but is no longer tappable, distinct
    // from "sold out" which is a different, still-relevant state. A cinema
    // with no seat map at all (see Cinema.hasSeatMap) disables every chip
    // the same way, for the same reason: nothing to usefully tap through to.
    final disabled = soldOut || isPast || !canOpenSeatMap;
    final t = AppLocalizations.of(context);
    // e.g. "SING ALONG", "Proiezione LASER 4K" - a different attribute than
    // Language (see groupSessionsByLanguage), so shown on the chip itself
    // rather than used to split sessions into rows.
    final specials = session.attributes
        .where((a) => a.attributeType == 'Session_Special')
        .map((a) => a.name)
        .toList();
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                soldOut
                    ? '${DateFormat.Hm().format(session.startTime)} · ${t.soldOut}'
                    : DateFormat.Hm().format(session.startTime),
                style: AppTheme.mono(context).copyWith(
                  fontSize: 13,
                  color: disabled
                      ? AppColors.textMuted
                      : AppColors.textPrimary,
                  decoration: soldOut ? TextDecoration.lineThrough : null,
                ),
              ),
              if (specials.isNotEmpty)
                Text(
                  specials.join(' · '),
                  style: AppTheme.body(context).copyWith(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
