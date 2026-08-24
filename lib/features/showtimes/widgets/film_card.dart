import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/date/clock.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/models/cinema.dart';
import '../../../core/models/film.dart';
import '../../../core/theme/app_theme.dart';
import '../../film_info/film_info_sheet.dart';
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
        posterImageSrc: film.posterImageSrc,
        runningTime: film.runningTime,
        showingGroups: film.showingGroups,
        initialSessionId: session.sessionId,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).now();
    void onTapSession(Session session) => _openSeatMap(context, ref, session);

    // Language captions (see _SessionsByLanguage) only make sense as their
    // own full-width rows - splitting a captioned group's chips between
    // "beside the poster" and "below" would separate some of its chips from
    // their own caption. So the beside/below split (see splitSessionsForPoster)
    // only applies when nothing needs a caption at all, the common case.
    final languageGroups = groupSessionsByLanguage(sessions);
    final hasLanguageCaptions =
        languageGroups.length > 1 || languageGroups.keys.any(isNotableLanguage);
    final split = hasLanguageCaptions
        ? null
        : splitSessionsForPoster(sessions);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              film.title,
                              style: AppTheme.display(
                                context,
                              ).copyWith(fontSize: 20, height: 1),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.info_outline, size: 20),
                            tooltip: AppLocalizations.of(context).filmInfoTooltip,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => showFilmInfoSheet(
                              context,
                              FilmInfoArgs(
                                title: film.title,
                                posterImageSrc: film.posterImageSrc,
                                runningTime: film.runningTime,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (film.runningTime != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${film.runningTime} min',
                          style: AppTheme.body(context).copyWith(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (split != null && split.beside.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _ChipsWrap(
                          sessions: split.beside,
                          now: now,
                          canOpenSeatMap: cinema.hasSeatMap,
                          onTapSession: onTapSession,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            // Whatever didn't fit beside the poster (or everything, when a
            // language caption is involved) continues here at the card's
            // full width rather than staying squeezed into the narrow
            // column - once a special-attribute badge (see _SessionTimeChip)
            // makes a chip wider than "16:00", that column only fits one
            // chip per line, turning what used to be a compact grid into a
            // tall, mostly-empty-on-the-left list.
            if (split == null || split.below.isNotEmpty) ...[
              const SizedBox(height: 8),
              _SessionsByLanguage(
                sessions: split?.below ?? sessions,
                now: now,
                canOpenSeatMap: cinema.hasSeatMap,
                onTapSession: onTapSession,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Approximate split of [sessions] into what should render beside the
/// poster versus below it at full width - not a real layout measurement
/// (a true "text wraps around a floated image" layout needs a custom
/// RenderObject, overkill for this), just a rough capacity estimate: a chip
/// with a special-attribute badge (two lines, see _SessionTimeChip) is
/// about as wide as the narrow column next to a poster on a typical phone,
/// so at most one fits per row there; a plain time-only chip is short
/// enough that a few fit per row. [_rowsBesidePoster] rows is roughly the
/// poster's own height.
const _rowsBesidePoster = 2;
const _plainChipsPerRow = 3;

typedef PosterSplit = ({List<Session> beside, List<Session> below});

PosterSplit splitSessionsForPoster(List<Session> sessions) {
  var rowsUsed = 0;
  var slotInRow = 0;
  final beside = <Session>[];
  final below = <Session>[];
  for (final session in sessions) {
    if (rowsUsed >= _rowsBesidePoster) {
      below.add(session);
      continue;
    }
    final hasBadge = session.attributes.any(
      (a) => a.attributeType != 'Language',
    );
    final rowCapacity = hasBadge ? 1 : _plainChipsPerRow;
    if (slotInRow >= rowCapacity) {
      rowsUsed++;
      slotInRow = 0;
      if (rowsUsed >= _rowsBesidePoster) {
        below.add(session);
        continue;
      }
    }
    beside.add(session);
    slotInRow++;
  }
  return (beside: beside, below: below);
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
    // More than one group always gets labels, for the same "which is which"
    // reason as before; a single group still gets one when its own language
    // isn't the default (see isNotableLanguage) - otherwise a lone
    // original-language showing with no dubbed alternative that day would
    // look exactly like an ordinary Italian one.
    final showLabels =
        groups.length > 1 || groups.keys.any(isNotableLanguage);

    if (!showLabels) {
      return _ChipsWrap(
        sessions: sessions,
        now: now,
        canOpenSeatMap: canOpenSeatMap,
        onTapSession: onTapSession,
      );
    }

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
          _ChipsWrap(
            sessions: entries[i].value,
            now: now,
            canOpenSeatMap: canOpenSeatMap,
            onTapSession: onTapSession,
          ),
        ],
      ],
    );
  }
}

class _ChipsWrap extends StatelessWidget {
  const _ChipsWrap({
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sessions.map((session) {
        return _SessionTimeChip(
          session: session,
          isPast: now.isAfter(session.startTime),
          canOpenSeatMap: canOpenSeatMap,
          onTap: () => onTapSession(session),
        );
      }).toList(),
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
    // Every non-Language attribute becomes a badge on the chip itself
    // instead of splitting sessions into rows the way Language does (see
    // groupSessionsByLanguage) - e.g. The Space's "SING ALONG"/"Proiezione
    // LASER 4K" (attributeType Session_Special), or UCI's own format tags
    // like "XL"/"3D"/"2D - SING ALONG" (attributeType screen). Deliberately
    // chain-agnostic: a new chain's own attribute types show up here for
    // free without this widget needing to know their names.
    final specials = session.attributes
        .where((a) => a.attributeType != 'Language')
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
