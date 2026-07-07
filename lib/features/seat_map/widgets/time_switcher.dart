import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/film.dart';
import '../../../core/theme/app_theme.dart';

/// Horizontal strip of every showtime this film has today, so switching
/// between them doesn't mean going back to the film list and tapping again.
/// A session that's sold out or already started is shown (still useful as a
/// record of the day) but not selectable - same rule as the film list.
class TimeSwitcher extends StatelessWidget {
  const TimeSwitcher({
    super.key,
    required this.sessions,
    required this.selectedSessionId,
    required this.now,
    required this.onSelect,
  });

  final List<Session> sessions;
  final String selectedSessionId;
  final DateTime now;
  final ValueChanged<Session> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sessions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final session = sessions[index];
          final isSelected = session.sessionId == selectedSessionId;
          final disabled = session.isSoldOut || now.isAfter(session.startTime);
          return ChoiceChip(
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
      ),
    );
  }
}
