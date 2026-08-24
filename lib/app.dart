import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/date/clock.dart';
import 'core/storage/film_info_store.dart';
import 'core/date/day_label.dart';
import 'core/localization/app_localizations.dart';
import 'core/localization/locale_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/no_stretch_scroll_behavior.dart';
import 'core/update/update_checker.dart';
import 'core/update/update_dialog.dart';
import 'features/cinema_picker/cinema_list_provider.dart';
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
    // Fire-and-forget, once per app process - same "housekeeping, not
    // something the UI waits on" shape as the update check. 60 days is
    // arbitrary but generous: this cache has no TTL otherwise (see
    // film_info_store.dart), only this startup sweep keeps it from growing
    // forever across months of use.
    ref
        .read(filmInfoStoreProvider)
        .purgeOlderThan(
          ref.read(clockProvider).now().subtract(const Duration(days: 60)),
        );
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  /// The actual fix for the official app's stale-"today" bug: every time the
  /// app comes back to the foreground, recompute the real calendar day from
  /// the device clock and compare it against the day we last saw. If it
  /// changed, drop the cached showing dates for the current favorite so
  /// they're refetched rather than silently served from yesterday.
  ///
  /// Films are no longer invalidated here (see films_provider.dart):
  /// they're now keyed by the literal calendar day being viewed, not by an
  /// abstract "today", so a rollover can't cause the old mislabeling bug -
  /// worst case a day's session list stays cached for up to its own TTL
  /// past the rollover, which clears on its own.
  Future<void> _checkForDayRollover() async {
    final currentDayKey = todayKey(ref.read(clockProvider).now());
    if (currentDayKey == _lastKnownDayKey) return;
    _lastKnownDayKey = currentDayKey;

    final activeCinema = await ref.read(activeCinemaProvider.future);
    if (activeCinema == null) return;
    ref.invalidate(showingDatesProvider(activeCinema));
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(effectiveLocaleProvider);
    return MaterialApp.router(
      title: 'Cinema: Disponibilità & Posti',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      scrollBehavior: const NoStretchScrollBehavior(),
      routerConfig: router,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Wraps whatever route is showing (picker, home, settings, ...) rather
      // than living on one particular screen - a fresh install lands on the
      // picker first (no favorite cinema yet), which would never trigger an
      // update check tied to the showtimes screen alone. This `context` is
      // inside the Navigator/Localizations tree the router builds, unlike
      // `TheSpaceApp`'s own.
      builder: (context, child) => _UpdateCheckGate(child: child),
    );
  }
}

class _UpdateCheckGate extends ConsumerStatefulWidget {
  const _UpdateCheckGate({required this.child});

  final Widget? child;

  @override
  ConsumerState<_UpdateCheckGate> createState() => _UpdateCheckGateState();
}

class _UpdateCheckGateState extends ConsumerState<_UpdateCheckGate> {
  /// Once per app *process*, not per rebuild of this gate.
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferUpdate());
  }

  /// The app is sideloaded (GitHub releases, no store), so this dialog is
  /// its only update channel - see update_checker.dart. Deliberately quiet:
  /// no update or any failure means nothing is shown at all.
  ///
  /// Uses [rootNavigatorKey] rather than this widget's own `context`: this
  /// gate lives in `MaterialApp.router`'s `builder`, which wraps the router
  /// (and its Navigator) from *outside* rather than being wrapped by it, so
  /// `context` here has no Navigator ancestor - confirmed live, `showDialog`
  /// threw "context does not include a Navigator" using it directly.
  Future<void> _maybeOfferUpdate() async {
    if (_checked) return;
    _checked = true;
    final update = await ref.read(updateCheckProvider.future);
    final navigatorContext = rootNavigatorKey.currentContext;
    if (update == null || navigatorContext == null || !navigatorContext.mounted) {
      return;
    }
    await showUpdateDialog(navigatorContext, update);
  }

  @override
  Widget build(BuildContext context) => widget.child!;
}
