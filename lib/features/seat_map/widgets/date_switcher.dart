import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/date/day_label.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import 'self_scrolling_chip_row.dart';

/// Every day this cinema has showings at all (not just this one film) - see
/// PROJECT_NOTES.md: for The Space/UCI this film's sessions are already
/// known for every one of these days ([SeatMapArgs.showingGroups] covers
/// everything in one response), so selecting any of them is instant; for
/// 18tickets-platform cinemas (RedCarpet, Multicinema Galleria, ...) only
/// the day the user came from is known upfront, so selecting any other one
/// triggers [SeatMapScreen] to fetch it lazily - [loadingDate]
/// is which one (if any) is currently in flight, shown as a small spinner
/// on that one chip, with every chip disabled meanwhile so a second tap
/// can't start an overlapping fetch.
///
/// Scrolls the selected day into view on its own, same as [TimeSwitcher] -
/// see [SelfScrollingChipRow].
class DateSwitcher extends StatelessWidget {
  const DateSwitcher({
    super.key,
    required this.availableDates,
    required this.selectedDate,
    required this.now,
    required this.onSelect,
    this.loadingDate,
  });

  // Labels vary more than time chips ("Oggi" vs "gio 9 lug"), so this is a
  // rougher estimate - it only needs to be close enough that the real chip
  // is already built (or built very soon after layout) for the precise
  // `ensureVisible` correction in [SelfScrollingChipRow] to have something
  // to find.
  static const _estimatedItemExtent = 100.0;

  final List<DateTime> availableDates;
  final DateTime selectedDate;
  final DateTime now;
  final ValueChanged<DateTime> onSelect;
  final DateTime? loadingDate;

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final isBusy = loadingDate != null;
    return SelfScrollingChipRow<DateTime>(
      items: availableDates,
      selectedIndex: availableDates.indexWhere(
        (d) => _isSameDay(d, selectedDate),
      ),
      estimatedItemExtent: _estimatedItemExtent,
      chipBuilder: (context, index, date, selectedKey) {
        final isSelected = _isSameDay(date, selectedDate);
        final isLoadingThis =
            loadingDate != null && _isSameDay(date, loadingDate!);
        return ChoiceChip(
          key: selectedKey,
          selected: isSelected,
          onSelected: isBusy ? null : (_) => onSelect(date),
          label: isLoadingThis
              ? const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_labelFor(context, date)),
          labelStyle: AppTheme.body(context).copyWith(
            color: isSelected ? const Color(0xFF211500) : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        );
      },
    );
  }

  String _labelFor(BuildContext context, DateTime date) {
    final t = AppLocalizations.of(context);
    switch (resolveDayLabel(date, now)) {
      case DayLabelKind.today:
        return t.today;
      case DayLabelKind.tomorrow:
        return t.tomorrow;
      case DayLabelKind.other:
        return DateFormat('EEE d MMM', t.dateFormatLocale).format(date);
    }
  }
}
