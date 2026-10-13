import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/localization/app_localizations.dart';
import 'package:thespace_companion/core/models/seat_map.dart';
import 'package:thespace_companion/features/seat_map/widgets/unnumbered_sectors.dart';

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
  testWidgets('known capacity: "N liberi su M"', (tester) async {
    await tester.pumpWidget(_app(const UnnumberedSectors(sectors: [
      UnnumberedSector(name: 'Posto Unico', freeSeats: 45, capacity: 60),
    ])));
    await tester.pumpAndSettle();
    expect(find.text('Posto Unico'), findsOneWidget);
    expect(find.text('45 liberi su 60'), findsOneWidget);
  });

  testWidgets('unknown capacity: only "N liberi", never a wrong total',
      (tester) async {
    await tester.pumpWidget(_app(const UnnumberedSectors(sectors: [
      UnnumberedSector(name: 'Loggione', freeSeats: 30, capacity: null),
    ])));
    await tester.pumpAndSettle();
    expect(find.text('30 liberi'), findsOneWidget);
  });
}
