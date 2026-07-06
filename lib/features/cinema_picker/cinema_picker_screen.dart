import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    await ref.read(favoriteCinemaStoreProvider).write(cinema.cinemaId);
    ref.invalidate(favoriteCinemaIdProvider);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final cinemasAsync = ref.watch(cinemaListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Scegli il tuo The Space')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Cerca città o cinema…',
                prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
              ),
            ),
          ),
          const FilmPerforationDivider(),
          Expanded(
            child: cinemasAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(
                  'Impossibile caricare la lista cinema.\n$err',
                  textAlign: TextAlign.center,
                ),
              ),
              data: (cinemas) {
                final filtered = _query.isEmpty
                    ? cinemas
                    : cinemas
                          .where(
                            (c) => c.name.toLowerCase().contains(
                              _query.toLowerCase(),
                            ),
                          )
                          .toList();
                if (filtered.isEmpty) {
                  return const Center(
                    child: Text(
                      'Nessun cinema trovato',
                      style: TextStyle(color: AppColors.textMuted),
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
                        cinema.name,
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
