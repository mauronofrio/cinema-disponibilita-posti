import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/localization/app_localizations.dart';
import 'package:thespace_companion/core/models/seat_map.dart';
import 'package:thespace_companion/features/seat_map/widgets/occupancy_summary.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('it'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

void main() {
  testWidgets('a map with no seats to count shows no "Occupati" text', (
    tester,
  ) async {
    final map = SeatMap(
      screenLabel: '',
      totalRows: 0,
      totalColumns: 0,
      rows: const [],
      areaCategories: const [],
      unnumberedSectors: const [
        UnnumberedSector(name: 'Posto Unico', freeSeats: 30, capacity: null),
      ],
    );
    await tester.pumpWidget(_app(OccupancySummary(seatMap: map)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Occupati'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('a normal map still shows the summary', (tester) async {
    final map = SeatMap(
      screenLabel: '',
      totalRows: 1,
      totalColumns: 2,
      rows: const [
        SeatRow(
          rowLabel: 'A',
          rowIndex: 0,
          seats: [
            Seat(
              rowIndex: 0,
              columnIndex: 0,
              name: '1',
              status: SeatStatus.available,
              areaCategoryCode: 'X',
            ),
            Seat(
              rowIndex: 0,
              columnIndex: 1,
              name: '2',
              status: SeatStatus.occupied,
              areaCategoryCode: 'X',
            ),
          ],
        ),
      ],
      areaCategories: const [],
    );
    await tester.pumpWidget(_app(OccupancySummary(seatMap: map)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Occupati'), findsOneWidget);
  });
}
