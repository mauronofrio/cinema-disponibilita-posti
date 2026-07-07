import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/cinema_picker/cinema_list_provider.dart';
import '../features/cinema_picker/cinema_picker_screen.dart';
import '../features/seat_map/seat_map_provider.dart';
import '../features/seat_map/seat_map_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/showtimes/showtimes_home_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final activeId = await ref.read(activeCinemaIdProvider.future);
      final goingToPicker = state.matchedLocation == '/picker';
      if (activeId == null && !goingToPicker) return '/picker';
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
