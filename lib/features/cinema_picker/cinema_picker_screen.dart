import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/models/cinema.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/film_perforation_divider.dart';
import 'cinema_list_provider.dart';

class CinemaPickerScreen extends ConsumerStatefulWidget {
  const CinemaPickerScreen({super.key});

  @override
  ConsumerState<CinemaPickerScreen> createState() => _CinemaPickerScreenState();
}

class _CinemaPickerScreenState extends ConsumerState<CinemaPickerScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _choose(Cinema cinema) async {
    await ref.read(favoriteCinemaStoreProvider).addAndActivate(cinema);
    ref.invalidate(favoriteCinemaIdsProvider);
    ref.invalidate(activeCinemaIdProvider);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final cinemasAsync = ref.watch(cinemaListProvider);
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t.pickCinemaTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: t.searchHint,
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
          const FilmPerforationDivider(),
          Expanded(
            child: cinemasAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(
                  '${t.cinemaListLoadError}\n$err',
                  textAlign: TextAlign.center,
                ),
              ),
              data: (cinemas) {
                final query = _query.toLowerCase();
                final filtered = query.isEmpty
                    ? cinemas
                    : cinemas
                          .where(
                            (c) =>
                                c.displayName.toLowerCase().contains(query) ||
                                c.address.toLowerCase().contains(query),
                          )
                          .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      t.noCinemaFound,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  );
                }
                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    0,
                    8,
                    0,
                    8 + MediaQuery.paddingOf(context).bottom,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final cinema = filtered[index];
                    return ListTile(
                      title: Text(
                        cinema.displayName,
                        style: AppTheme.display(context).copyWith(fontSize: 20),
                      ),
                      subtitle: Text(
                        cinema.address,
                        style: AppTheme.body(
                          context,
                        ).copyWith(color: AppColors.textMuted, fontSize: 13),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.textMuted,
                      ),
                      onTap: () => _choose(cinema),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
