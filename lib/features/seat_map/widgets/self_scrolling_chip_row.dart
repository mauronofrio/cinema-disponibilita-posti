import 'package:flutter/material.dart';

/// Horizontal strip of chips that scrolls its own selected item into view,
/// shared by [DateSwitcher] and [TimeSwitcher] (both a `ListView.separated`
/// over some list, with one item "selected" and the rest not).
///
/// The list only builds items near its current viewport. On first build
/// that viewport starts at an estimated offset (`selectedIndex *
/// estimatedItemExtent` - close enough that the real item is already built,
/// or built very soon after layout), so the precise correction in
/// [Scrollable.ensureVisible] has something to actually scroll to - without
/// the estimated jump, a selection far down the list would never get built
/// in the first place, and `ensureVisible` would have nothing to find.
class SelfScrollingChipRow<T> extends StatefulWidget {
  const SelfScrollingChipRow({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.estimatedItemExtent,
    required this.chipBuilder,
  });

  final List<T> items;

  /// Index of the currently-selected item in [items], or -1 if none.
  final int selectedIndex;

  /// Rough width of one chip (plus separator), used only to seed the
  /// scroll controller's initial offset - see class doc.
  final double estimatedItemExtent;

  /// Builds one chip. The builder is responsible for attaching [selectedKey]
  /// to its chip's `key` when `index == selectedIndex`, so this widget can
  /// find it to scroll to.
  final Widget Function(
    BuildContext context,
    int index,
    T item,
    Key? selectedKey,
  )
  chipBuilder;

  @override
  State<SelfScrollingChipRow<T>> createState() =>
      _SelfScrollingChipRowState<T>();
}

class _SelfScrollingChipRowState<T> extends State<SelfScrollingChipRow<T>> {
  final _selectedKey = GlobalKey();
  late final ScrollController _controller = ScrollController(
    initialScrollOffset: _estimatedInitialOffset(),
  );

  double _estimatedInitialOffset() {
    final index = widget.selectedIndex;
    return index <= 0 ? 0 : index * widget.estimatedItemExtent;
  }

  @override
  void initState() {
    super.initState();
    _scrollToSelected();
  }

  @override
  void didUpdateWidget(SelfScrollingChipRow<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) _scrollToSelected();
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
    return SizedBox(
      height: 40,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        itemCount: widget.items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selectedKey = index == widget.selectedIndex
              ? _selectedKey
              : null;
          return widget.chipBuilder(
            context,
            index,
            widget.items[index],
            selectedKey,
          );
        },
      ),
    );
  }
}
