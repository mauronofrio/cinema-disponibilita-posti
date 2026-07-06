import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../cinema_picker/cinema_list_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoriteAsync = ref.watch(favoriteCinemaProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Il tuo cinema',
            style: AppTheme.display(context).copyWith(fontSize: 20),
          ),
          const SizedBox(height: 8),
          favoriteAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (err, _) => Text('Errore: $err'),
            data: (cinema) => Card(
              child: ListTile(
                title: Text(cinema?.name ?? 'Nessun cinema selezionato'),
                subtitle: cinema == null
                    ? null
                    : Text(
                        cinema.address,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => context.push('/picker'),
            child: const Text('Cambia cinema'),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'App non ufficiale, senza alcun legame con The Space Cinema o Vue International. '
            'Non gestisce account, pagamenti, biglietti o prenotazioni: mostra soltanto '
            'programmazione e disponibilità posti, dati pubblicamente visibili sul sito ufficiale.',
            style: AppTheme.body(
              context,
            ).copyWith(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
