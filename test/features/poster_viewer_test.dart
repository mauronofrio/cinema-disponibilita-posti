import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/localization/app_localizations.dart';
import 'package:thespace_companion/features/poster_viewer/poster_viewer.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('it'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('PosterThumbnail', () {
    // flutter_test answers every network image with HTTP 400, so the image
    // itself always "fails" here - which conveniently also covers the
    // "a poster that failed to load stays tappable" case.
    testWidgets('tapping a poster opens it full screen, zoomable', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const PosterThumbnail(
            url: 'https://example.com/poster.jpg',
            width: 64,
            height: 96,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PosterViewer), findsNothing);

      await tester.tap(find.byType(PosterThumbnail));
      await tester.pumpAndSettle();

      expect(find.byType(PosterViewer), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('the close button dismisses the viewer', (tester) async {
      await tester.pumpWidget(
        _app(
          const PosterThumbnail(
            url: 'https://example.com/poster.jpg',
            width: 64,
            height: 96,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PosterThumbnail));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Chiudi'));
      await tester.pumpAndSettle();

      expect(find.byType(PosterViewer), findsNothing);
    });

    testWidgets('no poster URL means a plain placeholder: tapping it opens '
        'nothing, since there is nothing to show', (tester) async {
      await tester.pumpWidget(
        _app(const PosterThumbnail(url: null, width: 64, height: 96)),
      );
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PosterThumbnail));
      await tester.pumpAndSettle();

      expect(find.byType(PosterViewer), findsNothing);
    });
    testWidgets('double tap zooms in, a second double tap zooms back out', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const PosterViewer(url: 'https://example.com/poster.jpg')),
      );
      await tester.pumpAndSettle();

      double scale() => tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis();

      Future<void> doubleTap() async {
        final center = tester.getCenter(find.byType(InteractiveViewer));
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(center);
        await tester.pumpAndSettle();
      }

      expect(scale(), 1.0);
      await doubleTap();
      expect(scale(), closeTo(2.5, 0.01));
      await doubleTap();
      expect(scale(), 1.0);
    });
  });
}
