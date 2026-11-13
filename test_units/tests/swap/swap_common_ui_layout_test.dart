import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

import 'swap_common_ui_fakes.dart';

/// The swap surface's column, surfaces, headings and announcements.
void main() {
  const dark = SwapPalette.dark;
  const probe = Key('probe');

  group('swap layout', () {
    useSwapUi();

    group('column', () {
      const content = SizedBox(key: probe, height: 10, width: double.infinity);

      testWidgets('centres the readable width at the top of a wide screen', (
        tester,
      ) async {
        await pumpSwapUi(
          tester,
          const SwapColumn(child: content),
          size: const Size(1024, 768),
        );

        expect(
          tester.getRect(find.byKey(probe)),
          const Rect.fromLTWH(240, 20, 544, 10),
        );
      });

      testWidgets('fills a phone, inside its padding', (tester) async {
        await pumpSwapUi(tester, const SwapColumn(child: content));

        expect(
          tester.getRect(find.byKey(probe)),
          const Rect.fromLTWH(16, 20, 388, 10),
        );
      });

      testWidgets('takes a padding of its own', (tester) async {
        await pumpSwapUi(
          tester,
          const SwapColumn(padding: EdgeInsets.zero, child: content),
          size: const Size(1024, 768),
        );

        expect(
          tester.getRect(find.byKey(probe)),
          const Rect.fromLTWH(224, 0, SwapGeometry.contentWidth, 10),
        );
      });
    });

    group('surface', () {
      BoxDecoration decorationOf(WidgetTester tester) =>
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byType(SwapSurface),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;

      testWidgets('is the surface colour with a hairline, padded', (
        tester,
      ) async {
        await pumpSwapUi(
          tester,
          const Align(
            alignment: Alignment.topLeft,
            child: SwapSurface(
              child: SizedBox(key: probe, width: 20, height: 20),
            ),
          ),
        );

        final decoration = decorationOf(tester);
        expect(decoration.color, dark.surface);
        expect(decoration.border, Border.all(color: dark.border));
        expect(decoration.borderRadius, BorderRadius.circular(16));
        expect(tester.getTopLeft(find.byKey(probe)), const Offset(14, 14));
      });

      testWidgets('follows the light theme', (tester) async {
        await pumpSwapUi(
          tester,
          const SwapSurface(child: SizedBox()),
          dark: false,
        );

        expect(decorationOf(tester).color, SwapPalette.light.surface);
        expect(
          decorationOf(tester).border,
          Border.all(color: SwapPalette.light.border),
        );
      });

      testWidgets('takes its own colours, radius and padding', (tester) async {
        final tint = dark.brand.withValues(alpha: 0.2);
        await pumpSwapUi(
          tester,
          Align(
            alignment: Alignment.topLeft,
            child: SwapSurface(
              color: tint,
              borderColor: dark.brand,
              radius: 4,
              padding: const EdgeInsets.all(2),
              child: const SizedBox(key: probe, width: 20, height: 20),
            ),
          ),
        );

        final decoration = decorationOf(tester);
        expect(decoration.color, tint);
        expect(decoration.border, Border.all(color: dark.brand));
        expect(decoration.borderRadius, BorderRadius.circular(4));
        expect(tester.getTopLeft(find.byKey(probe)), const Offset(2, 2));
      });
    });

    group('page heading', () {
      testWidgets('announces the title as a heading', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpSwapUi(tester, const SwapPageHeading(title: 'Activity'));

        final data = tester
            .getSemantics(find.text('Activity'))
            .getSemanticsData();
        expect(data.label, 'Activity');
        expect(data.flagsCollection.isHeader, isTrue);
        expect(tester.widget<Text>(find.text('Activity')).style!.fontSize, 28);
        semantics.dispose();
      });

      testWidgets('sets a subtitle under the title', (tester) async {
        await pumpSwapUi(
          tester,
          const SwapPageHeading(title: 'Activity', subtitle: 'All your swaps'),
        );

        final title = tester.getRect(find.text('Activity'));
        final subtitle = tester.getRect(find.text('All your swaps'));
        expect(subtitle.top, title.bottom + 4);
        expect(subtitle.left, title.left);
      });

      testWidgets('puts a leading action before the title', (tester) async {
        await pumpSwapUi(
          tester,
          const SwapPageHeading(
            title: 'Review swap',
            leading: SizedBox(key: probe, width: 48, height: 48),
          ),
        );

        expect(
          tester.getTopLeft(find.text('Review swap')).dx,
          tester.getTopRight(find.byKey(probe)).dx + 12,
        );
      });

      testWidgets('keeps space below itself', (tester) async {
        await pumpSwapUi(
          tester,
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwapPageHeading(title: 'Swap'),
              SizedBox(key: probe, height: 1),
            ],
          ),
        );

        expect(
          tester.getTopLeft(find.byKey(probe)).dy,
          tester.getBottomLeft(find.byType(SwapPageHeading)).dy,
        );
        expect(
          tester.getSize(find.byType(SwapPageHeading)).height,
          tester.getSize(find.text('Swap')).height + 18,
        );
      });
    });

    group('announcements', () {
      Widget announcer() => Builder(
        builder: (context) => TextButton(
          onPressed: () => swapAnnounce(context, 'Quote ready'),
          child: const Text('Announce'),
        ),
      );

      testWidgets('reach assistive technology where the platform supports '
          'them', (tester) async {
        await pumpSwapUi(
          tester,
          announcer(),
          media: (
            textScale: 1,
            boldText: false,
            reduceMotion: false,
            announces: true,
          ),
        );
        await tester.tap(find.text('Announce'));
        await tester.pump();

        expect(tester.takeAnnouncements(), [
          isAccessibilityAnnouncement(
            'Quote ready',
            textDirection: TextDirection.ltr,
            assertiveness: Assertiveness.polite,
          ),
        ]);
      });

      testWidgets('are skipped where it does not', (tester) async {
        await pumpSwapUi(tester, announcer());
        await tester.tap(find.text('Announce'));
        await tester.pump();

        expect(tester.takeAnnouncements(), isEmpty);
      });
    });
  });
}
