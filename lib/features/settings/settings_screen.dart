import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/models/cinema.dart';
import '../../core/storage/favorite_cinema_store.dart';
import '../../core/theme/app_theme.dart';
import '../cinema_picker/cinema_list_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _setActive(WidgetRef ref, Cinema cinema) async {
    await ref.read(favoriteCinemaStoreProvider).setActive(cinema);
    ref.invalidate(activeCinemaIdProvider);
  }

  Future<void> _remove(WidgetRef ref, Cinema cinema) async {
    await ref.read(favoriteCinemaStoreProvider).remove(cinema);
    ref.invalidate(favoriteCinemaIdsProvider);
    ref.invalidate(activeCinemaIdProvider);
  }

  Future<void> _setLanguage(WidgetRef ref, String languageCode) async {
    await ref.read(languageStoreProvider).setOverride(languageCode);
    ref.invalidate(languageOverrideProvider);
  }

  Widget _cinemaCard(
    WidgetRef ref,
    AppLocalizations t,
    Cinema cinema,
    String? activeId,
  ) {
    final isActive = FavoriteCinemaStore.keyFor(cinema) == activeId;
    return Card(
      child: ListTile(
        leading: Icon(
          isActive ? Icons.radio_button_checked : Icons.radio_button_off,
          color: isActive ? AppColors.marquee : AppColors.textMuted,
        ),
        title: Text(cinema.displayName),
        subtitle: Text(
          cinema.address,
          style: const TextStyle(color: AppColors.textMuted),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: t.removeCinema,
          onPressed: () => _remove(ref, cinema),
        ),
        onTap: isActive ? null : () => _setActive(ref, cinema),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoriteCinemasProvider);
    final activeIdAsync = ref.watch(activeCinemaIdProvider);
    final locale = ref.watch(effectiveLocaleProvider);
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t.settingsTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text(
            t.yourCinemas,
            style: AppTheme.display(context).copyWith(fontSize: 20),
          ),
          const SizedBox(height: 8),
          favoritesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Text('${t.genericError} $err'),
            data: (cinemas) {
              final activeId = activeIdAsync.value;
              if (cinemas.isEmpty) {
                return Card(child: ListTile(title: Text(t.noCinemaSelected)));
              }
              return Column(
                children: [
                  for (final cinema in cinemas) ...[
                    _cinemaCard(ref, t, cinema, activeId),
                    if (cinema != cinemas.last) const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => context.push('/picker'),
            child: Text(t.addCinema),
          ),
          const SizedBox(height: 32),
          Text(
            t.language,
            style: AppTheme.display(context).copyWith(fontSize: 20),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('EN'),
                  Switch(
                    value: locale.languageCode == 'it',
                    onChanged: (isItalian) =>
                        _setLanguage(ref, isItalian ? 'it' : 'en'),
                  ),
                  const Text('IT'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            t.disclaimer,
            style: AppTheme.body(
              context,
            ).copyWith(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => launchUrl(
              Uri.parse(
                'https://github.com/mauronofrio/cinema-disponibilita-posti',
              ),
              mode: LaunchMode.externalApplication,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.string(
                  _githubMarkSvg,
                  width: 16,
                  height: 16,
                  colorFilter: const ColorFilter.mode(
                    AppColors.textPrimary,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  t.sourceCode,
                  style: AppTheme.body(
                    context,
                  ).copyWith(color: AppColors.textPrimary, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// GitHub's own "mark" logo (the octocat glyph, `viewBox="0 0 16 16"`),
/// tinted at render time via [ColorFilter] rather than shipped as a
/// separate asset per color/density - this is the only place in the app
/// that needs it.
const _githubMarkSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
<path fill="#fff" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z"/>
</svg>
''';
