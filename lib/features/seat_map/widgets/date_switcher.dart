import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/date/day_label.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_theme.dart';

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
/// Scrolls the selected day into view on its own, same as [TimeSwitcher].
class DateSwitcher extends StatefulWidget {
  const DateSwitcher({
    super.key,
    required this.availableDates,
    required this.selectedDate,
    required this.now,
    required this.onSelect,
    this.loadingDate,
  });

  final List<DateTime> availableDates;
  final DateTime selectedDate;
  final DateTime now;
  final ValueChanged<DateTime> onSelect;
  final DateTime? loadingDate;

  @override
  State<DateSwitcher> createState() => _DateSwitcherState();
}

class _DateSwitcherState extends State<DateSwitcher> {
  // Labels vary more than time chips ("Oggi" vs "gio 9 lug"), so this is a
  // rougher estimate - it only needs to be close enough that the real chip
  // is already built (or built very soon after layout) for the precise
  // `ensureVisible` correction below to have something to find.
  static const _estimatedItemExtent = 100.0;

  final _selectedKey = GlobalKey();
  late final ScrollController _controller = ScrollController(
    initialScrollOffset: _estimatedInitialOffset(),
  );

  double _estimatedInitialOffset() {
    final index = widget.availableDates.indexWhere(
      (d) => _isSameDay(d, widget.selectedDate),
    );
    return index <= 0 ? 0 : index * _estimatedItemExtent;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void initState() {
    super.initState();
    _scrollToSelected();
  }

  @override
  void didUpdateWidget(DateSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) _scrollToSelected();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selectedContext = _selectedKey.currentContext;
      if (selectedContext == null) return;
      Scrollable.ensureVisible(
        selectedContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = widget.loadingDate != null;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        itemCount: widget.availableDates.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final date = widget.availableDates[index];
          final isSelected = _isSameDay(date, widget.selectedDate);
          final isLoadingThis =
              widget.loadingDate != null &&
              _isSameDay(date, widget.loadingDate!);
          return ChoiceChip(
            key: isSelected ? _selectedKey : null,
            selected: isSelected,
            onSelected: isBusy ? null : (_) => widget.onSelect(date),
            label: isLoadingThis
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_labelFor(context, date)),
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

  String _labelFor(BuildContext context, DateTime date) {
    final t = AppLocalizations.of(context);
    switch (resolveDayLabel(date, widget.now)) {
      case DayLabelKind.today:
        return t.today;
      case DayLabelKind.tomorrow:
        return t.tomorrow;
      case DayLabelKind.other:
        return DateFormat('EEE d MMM', t.dateFormatLocale).format(date);
    }
  }
}
