import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/date/clock.dart';
import 'core/date/day_label.dart';
import 'core/theme/app_theme.dart';
import 'features/cinema_picker/cinema_list_provider.dart';
import 'features/showtimes/films_provider.dart';
import 'features/showtimes/showing_dates_provider.dart';
import 'routing/app_router.dart';

class TheSpaceApp extends ConsumerStatefulWidget {
  const TheSpaceApp({super.key});

  @override
  ConsumerState<TheSpaceApp> createState() => _TheSpaceAppState();
}

class _TheSpaceAppState extends ConsumerState<TheSpaceApp> {
  AppLifecycleListener? _lifecycleListener;
  String? _lastKnownDayKey;

  @override
  void initState() {
    super.initState();
    _lastKnownDayKey = todayKey(ref.read(clockProvider).now());
    _lifecycleListener = AppLifecycleListener(onResume: _checkForDayRollover);
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  /// The actual fix for the official app's stale-"today" bug: every time the
  /// app comes back to the foreground, recompute the real calendar day from
  /// the device clock and compare it against the day we last saw. If it
  /// changed, drop the cached showings/films for the current favorite so
  /// they're refetched rather than silently served from yesterday.
  Future<void> _checkForDayRollover() async {
    final currentDayKey = todayKey(ref.read(clockProvider).now());
    if (currentDayKey == _lastKnownDayKey) return;
    _lastKnownDayKey = currentDayKey;

    final favoriteId = await ref.read(favoriteCinemaIdProvider.future);
    if (favoriteId == null) return;
    ref.invalidate(showingDatesProvider(favoriteId));
    ref.invalidate(filmsForCinemaProvider(favoriteId));
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'The Space (non ufficiale)',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
      locale: const Locale('it'),
      supportedLocales: const [Locale('it')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
