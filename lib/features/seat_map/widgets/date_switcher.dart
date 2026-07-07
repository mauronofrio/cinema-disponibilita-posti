import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/date/day_label.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/models/film.dart';
import '../../../core/theme/app_theme.dart';

/// Every day this film is showing at this cinema, so switching to "domani"
/// doesn't mean leaving the seat map screen - the data is already at hand
/// ([SeatMapArgs.showingGroups] covers every day in one response), so this
/// costs nothing extra to offer.
///
/// Scrolls the selected day into view on its own, same as [TimeSwitcher].
class DateSwitcher extends StatefulWidget {
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
    final available = widget.showingGroups
        .where((g) => g.sessions.isNotEmpty)
        .toList();
    final index = available.indexWhere(
      (g) =>
          g.date.year == widget.selectedDate.year &&
          g.date.month == widget.selectedDate.month &&
          g.date.day == widget.selectedDate.day,
    );
    return index <= 0 ? 0 : index * _estimatedItemExtent;
  }

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
    final available = widget.showingGroups
        .where((g) => g.sessions.isNotEmpty)
        .toList();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        itemCount: available.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final group = available[index];
          final isSelected =
              group.date.year == widget.selectedDate.year &&
              group.date.month == widget.selectedDate.month &&
              group.date.day == widget.selectedDate.day;
          return ChoiceChip(
            key: isSelected ? _selectedKey : null,
            selected: isSelected,
            onSelected: (_) => widget.onSelect(group.date),
            label: Text(_labelFor(context, group.date)),
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
