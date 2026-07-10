import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/film.dart';
import '../../../core/theme/app_theme.dart';
import 'self_scrolling_chip_row.dart';

/// Horizontal strip of every showtime this film has today, so switching
/// between them doesn't mean going back to the film list and tapping again.
/// A session that's sold out or already started is shown (still useful as a
/// record of the day) but not selectable - same rule as the film list.
///
/// Scrolls the selected time into view on its own - with many showtimes,
/// jumping straight to the seat map for one of the last ones would otherwise
/// leave the strip showing its start, with the actual selection off-screen.
/// See [SelfScrollingChipRow].
class TimeSwitcher extends StatelessWidget {
  const TimeSwitcher({
    super.key,
    required this.sessions,
    required this.selectedSessionId,
    required this.now,
    required this.onSelect,
  });

  // Chips are all "HH:MM" in a monospace font, so their width barely varies -
  // good enough to estimate where the selected one roughly is.
  static const _estimatedItemExtent = 78.0;

  final List<Session> sessions;
  final String selectedSessionId;
  final DateTime now;
  final ValueChanged<Session> onSelect;

  @override
  Widget build(BuildContext context) {
    return SelfScrollingChipRow<Session>(
      items: sessions,
      selectedIndex: sessions.indexWhere(
        (s) => s.sessionId == selectedSessionId,
      ),
      estimatedItemExtent: _estimatedItemExtent,
      chipBuilder: (context, index, session, selectedKey) {
        final isSelected = session.sessionId == selectedSessionId;
        final disabled = session.isSoldOut || now.isAfter(session.startTime);
        return ChoiceChip(
          key: selectedKey,
          selected: isSelected,
          onSelected: disabled ? null : (_) => onSelect(session),
          label: Text(DateFormat.Hm().format(session.startTime)),
          labelStyle: AppTheme.mono(context).copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? const Color(0xFF211500)
                : (disabled ? AppColors.textMuted : AppColors.textPrimary),
            decoration: session.isSoldOut ? TextDecoration.lineThrough : null,
          ),
        );
      },
    );
  }
}
