import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/cinema_picker/cinema_list_provider.dart';
import '../features/cinema_picker/cinema_picker_screen.dart';
import '../features/seat_map/seat_map_provider.dart';
import '../features/seat_map/seat_map_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/showtimes/showtimes_home_screen.dart';

/// A handle onto go_router's own Navigator, from outside the widget tree it
/// builds - needed anywhere that must show a dialog/route but only has a
/// `context` from above the router (e.g. `MaterialApp.router`'s own
/// `builder`, which wraps the router rather than being wrapped by it - see
/// `_UpdateCheckGate` in app.dart).
final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) async {
      // Must check the *resolved* cinema, not just whether some id string is
      // stored - a stored id that no longer matches any cinema (e.g. a
      // favorite saved under an older, since-changed key format) needs the
      // same redirect as "no favorite at all", or the home screen is left
      // showing nothing forever waiting for a redirect that never comes
      // (confirmed live: this exact case needed a full app-data reset to
      // recover before this fix).
      final activeCinema = await ref.read(activeCinemaProvider.future);
      final goingToPicker = state.matchedLocation == '/picker';
      if (activeCinema == null && !goingToPicker) return '/picker';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const ShowtimesHomeScreen(),
      ),
      GoRoute(
        path: '/picker',
        builder: (context, state) => const CinemaPickerScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/seat-map',
        builder: (context, state) =>
            SeatMapScreen(args: state.extra as SeatMapArgs),
      ),
    ],
  );
});
