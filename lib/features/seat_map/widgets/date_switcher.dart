import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/date/day_label.dart';
import '../../../core/models/film.dart';
import '../../../core/theme/app_theme.dart';

/// Every day this film is showing at this cinema, so switching to "domani"
/// doesn't mean leaving the seat map screen - the data is already at hand
/// ([SeatMapArgs.showingGroups] covers every day in one response), so this
/// costs nothing extra to offer.
class DateSwitcher extends StatelessWidget {
  const DateSwitcher({
    super.key,
    required this.showingGroups,
    required this.selectedDate,
    required this.now,
    required this.onSelect,
  });

  final List<ShowingGroup> showingGroups;
  final DateTime selectedDate;
  final DateTime now;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final available = showingGroups
        .where((g) => g.sessions.isNotEmpty)
        .toList();
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: available.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final group = available[index];
          final isSelected =
              group.date.year == selectedDate.year &&
              group.date.month == selectedDate.month &&
              group.date.day == selectedDate.day;
          return ChoiceChip(
            selected: isSelected,
            onSelected: (_) => onSelect(group.date),
            label: Text(_labelFor(group.date)),
            labelStyle: AppTheme.body(context).copyWith(
              color: isSelected
                  ? const Color(0xFF211500)
                  : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          );
        },
      ),
    );
  }

  String _labelFor(DateTime date) {
    switch (resolveDayLabel(date, now)) {
      case DayLabelKind.today:
        return 'Oggi';
      case DayLabelKind.tomorrow:
        return 'Domani';
      case DayLabelKind.other:
        return DateFormat('EEE d MMM', 'it_IT').format(date);
    }
  }
}
