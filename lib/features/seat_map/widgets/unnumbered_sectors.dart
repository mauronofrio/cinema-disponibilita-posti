import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/models/seat_map.dart';
import '../../../core/theme/app_theme.dart';

/// Sectors sold without seat numbers ("Posto Unico") - no grid exists for
/// them, so each is a name and how many places are left.
class UnnumberedSectors extends StatelessWidget {
  const UnnumberedSectors({super.key, required this.sectors});

  final List<UnnumberedSector> sectors;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in sectors)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.event_seat_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(s.name)),
                Text(
                  t.unnumberedSectorFree(s.freeSeats, s.capacity),
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
