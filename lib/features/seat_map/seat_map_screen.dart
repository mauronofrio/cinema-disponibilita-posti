import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import 'seat_map_provider.dart';
import 'widgets/area_legend.dart';
import 'widgets/seat_grid.dart';

/// Read-only seat map: no seat is tappable/selectable, there is no checkout.
/// The entire point is "can I see, at a glance, what's free" - so loading
/// calls only the seats endpoint directly (see [TheSpaceApiClient.getSeatMapJson]),
/// skipping the order/payment/concessions flow the official app/website
/// trigger unnecessarily on the same tap.
class SeatMapScreen extends ConsumerWidget {
  const SeatMapScreen({super.key, required this.args});

  final SeatMapArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (args.cinemaId, args.sessionId);
    final seatMapAsync = ref.watch(seatMapProvider(key));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          args.filmTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(seatMapProvider(key));
          await ref.read(seatMapProvider(key).future);
        },
        child: ListView(
          // Android 15+ edge-to-edge means the system nav bar floats over the
          // app rather than reserving its own space, so the bottom inset has
          // to be added explicitly or the last rows of the grid end up
          // permanently hidden behind it.
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            Text(
              '${args.screenName} · ${DateFormat.Hm().format(args.startTime)}',
              style: AppTheme.body(
                context,
              ).copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            seatMapAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    'Impossibile caricare i posti.\n$err',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (seatMap) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AreaLegend(seatMap: seatMap),
                    const SizedBox(height: 20),
                    SeatGrid(seatMap: seatMap),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
