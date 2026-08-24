import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import 'film_info_provider.dart';

/// Just enough to show the header immediately (poster/title/runtime are
/// already known to the caller, no fetch needed for those) while
/// filmInfoProvider resolves the rest.
class FilmInfoArgs {
  const FilmInfoArgs({
    required this.title,
    required this.posterImageSrc,
    required this.runningTime,
  });

  final String title;
  final String? posterImageSrc;
  final int? runningTime;
}

Future<void> showFilmInfoSheet(BuildContext context, FilmInfoArgs args) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => FilmInfoSheet(args: args),
  );
}

class FilmInfoSheet extends ConsumerWidget {
  const FilmInfoSheet({super.key, required this.args});

  final FilmInfoArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    // Watching this here is what actually triggers the fetch - nothing
    // calls filmInfoProvider before this sheet is opened.
    final infoAsync = ref.watch(filmInfoProvider(args.title));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: args.posterImageSrc == null
                      ? Container(
                          width: 120,
                          height: 180,
                          color: AppColors.surfaceElevated,
                        )
                      : Image.network(
                          args.posterImageSrc!,
                          width: 120,
                          height: 180,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 120,
                            height: 180,
                            color: AppColors.surfaceElevated,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                args.title,
                style: AppTheme.display(context).copyWith(fontSize: 22),
              ),
              if (args.runningTime != null) ...[
                const SizedBox(height: 2),
                Text(
                  '${args.runningTime} min',
                  style: AppTheme.body(
                    context,
                  ).copyWith(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              infoAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (err, _) => Text(
                  t.filmInfoUnavailable,
                  style: AppTheme.body(
                    context,
                  ).copyWith(color: AppColors.textMuted),
                ),
                data: (info) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.overview, style: AppTheme.body(context)),
                    if (info.trailerUrl != null) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(info.trailerUrl!),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(t.watchTrailer),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
