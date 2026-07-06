import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/date/day_label.dart';
import '../../../core/models/showing_date.dart';
import '../../../core/theme/app_theme.dart';

/// Horizontal strip of day chips. Labels are derived from [now] every build
/// via [resolveDayLabel] - never trusted from a cached value - so this
/// widget alone can't reproduce the official app's stale-"today" bug even if
/// the underlying [ShowingDate] list came from a stale cache.
class DaySelector extends StatelessWidget {
  const DaySelector({
    super.key,
    required this.days,
    required this.selected,
    required this.now,
    required this.onSelect,
  });

  final List<ShowingDate> days;
  final DateTime selected;
  final DateTime now;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final available = days.where((d) => d.hasShowings).toList();
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: available.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = available[index];
          final isSelected =
              day.date.year == selected.year &&
              day.date.month == selected.month &&
              day.date.day == selected.day;
          return ChoiceChip(
            selected: isSelected,
            onSelected: (_) => onSelect(day.date),
            label: Text(_labelFor(day.date)),
            labelStyle: TextStyle(
              color: isSelected
                  ? const Color(0xFF211500)
                  : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
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
