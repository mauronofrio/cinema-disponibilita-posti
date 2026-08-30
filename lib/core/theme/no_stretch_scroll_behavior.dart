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

  /// The "no stretch" part of this class is [buildOverscrollIndicator]
  /// above, not this - the indicator is what draws the rubber-band, the
  /// physics only decide whether a drag is accepted at all.
  ///
  /// That distinction matters: plain [ClampingScrollPhysics] refuses the
  /// drag outright when the content already fits on screen
  /// (`shouldAcceptUserOffset` is false once `minScrollExtent ==
  /// maxScrollExtent`), so no scroll notification is ever emitted and any
  /// `RefreshIndicator` above it never arms. That silently disabled
  /// pull-to-refresh in exactly the cases where it's needed most: a short
  /// error message, or a small screening room - the user pulls, nothing
  /// moves, and there's no other way to retry.
  ///
  /// [AlwaysScrollableScrollPhysics] restores "always accept the drag"
  /// while delegating the actual feel to the clamping parent, so the list
  /// still doesn't rubber-band and still has no glow.
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics());
}
