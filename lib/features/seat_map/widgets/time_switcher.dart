import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/film.dart';
import '../../../core/theme/app_theme.dart';

/// Horizontal strip of every showtime this film has today, so switching
/// between them doesn't mean going back to the film list and tapping again.
/// A session that's sold out or already started is shown (still useful as a
/// record of the day) but not selectable - same rule as the film list.
///
/// Scrolls the selected time into view on its own - with many showtimes,
/// jumping straight to the seat map for one of the last ones would otherwise
/// leave the strip showing its start, with the actual selection off-screen.
class TimeSwitcher extends StatefulWidget {
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
  State<TimeSwitcher> createState() => _TimeSwitcherState();
}

class _TimeSwitcherState extends State<TimeSwitcher> {
  // Chips are all "HH:MM" in a monospace font, so their width barely varies -
  // good enough to estimate where the selected one roughly is.
  static const _estimatedItemExtent = 78.0;

  final _selectedKey = GlobalKey();
  late final ScrollController _controller = ScrollController(
    initialScrollOffset: _estimatedInitialOffset(),
  );

  double _estimatedInitialOffset() {
    final index = widget.sessions.indexWhere(
      (s) => s.sessionId == widget.selectedSessionId,
    );
    return index <= 0 ? 0 : index * _estimatedItemExtent;
  }

  @override
  void initState() {
    super.initState();
    _scrollToSelected();
  }

  @override
  void didUpdateWidget(TimeSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSessionId != widget.selectedSessionId) {
      _scrollToSelected();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToSelected() {
    // The list only builds items near its current viewport. On first build
    // that viewport starts at the estimated offset above (close enough for
    // the real item to already be built or built very soon after layout),
    // so this precise correction has something to actually scroll to -
    // without the estimated jump, a selection far down the list would never
    // get built in the first place, and `ensureVisible` would have nothing
    // to find.
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
    return SizedBox(
      height: 40,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        itemCount: widget.sessions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final session = widget.sessions[index];
          final isSelected = session.sessionId == widget.selectedSessionId;
          final disabled =
              session.isSoldOut || widget.now.isAfter(session.startTime);
          return ChoiceChip(
            key: isSelected ? _selectedKey : null,
            selected: isSelected,
            onSelected: disabled ? null : (_) => widget.onSelect(session),
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
