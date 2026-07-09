import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/models/cinema.dart';
import '../../core/theme/app_theme.dart';
import '../cinema_picker/cinema_list_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _setActive(WidgetRef ref, Cinema cinema) async {
    await ref.read(favoriteCinemaStoreProvider).setActive(cinema.cinemaId);
    ref.invalidate(activeCinemaIdProvider);
  }

  Future<void> _remove(WidgetRef ref, Cinema cinema) async {
    await ref.read(favoriteCinemaStoreProvider).remove(cinema.cinemaId);
    ref.invalidate(favoriteCinemaIdsProvider);
    ref.invalidate(activeCinemaIdProvider);
  }

  Future<void> _setLanguage(WidgetRef ref, String languageCode) async {
    await ref.read(languageStoreProvider).setOverride(languageCode);
    ref.invalidate(languageOverrideProvider);
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
                    Card(
                      child: ListTile(
                        leading: Icon(
                          cinema.cinemaId == activeId
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: cinema.cinemaId == activeId
                              ? AppColors.marquee
                              : AppColors.textMuted,
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
                        onTap: cinema.cinemaId == activeId
                            ? null
                            : () => _setActive(ref, cinema),
                      ),
                    ),
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
                const Icon(
                  Icons.code,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  t.sourceCode,
                  style: AppTheme.body(context).copyWith(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
