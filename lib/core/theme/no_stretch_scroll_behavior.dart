import 'package:flutter/material.dart';

/// Removes Android's default "stretch" overscroll effect app-wide: scrolling
/// past the end of a list just stops, instead of the content rubber-banding.
/// Set once on `MaterialApp.router` rather than patched into every
/// individual scroll view.
class NoStretchScrollBehavior extends MaterialScrollBehavior {
  const NoStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}
