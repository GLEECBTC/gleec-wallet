import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

import 'swap_common_ui_fakes.dart';

/// Badges, callouts, helper lines, heroes, questions and count dots: the
/// swap surface's ways of saying how things stand.
void main() {
  const dark = SwapPalette.dark;
  const bold = (
    textScale: 1.0,
    boldText: true,
    reduceMotion: false,
    announces: false,
  );

  BoxDecoration decorationIn(WidgetTester tester, Type widget) =>
      tester
              .widget<DecoratedBox>(
                find
                    .descendant(
                      of: find.byType(widget),
                      matching: find.byType(DecoratedBox),
                    )
                    .first,
              )
              .decoration
          as BoxDecoration;

  Color? textColor(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color;

  Color? iconColor(WidgetTester tester, IconData icon) =>
      tester.widget<Icon>(find.byIcon(icon)).color;

  group('swap status widgets', () {
    useSwapUi();

    group('badge', () {
      testWidgets('each tone has its colours', (tester) async {
        for (final tone in SwapTone.values) {
          await pumpSwapUi(
            tester,
            Center(
              child: SwapBadge(label: 'Best net return', tone: tone),
            ),
          );
          final decoration = decorationIn(tester, SwapBadge);
          expect(
            decoration.color,
            dark.toneBackground(tone),
            reason: tone.name,
          );
          expect(
            decoration.border,
            Border.all(color: dark.toneBorder(tone)),
            reason: tone.name,
          );
          expect(
            textColor(tester, 'Best net return'),
            dark.toneColor(tone),
            reason: tone.name,
          );
        }
      });

      testWidgets('is a neutral pill at least 28 tall, icon first', (
        tester,
      ) async {
        await pumpSwapUi(
          tester,
          const Center(
            child: SwapBadge(label: 'Expires in 18s', icon: Icons.timer),
          ),
        );

        expect(tester.getSize(find.byType(SwapBadge)).height, 28);
        expect(
          iconColor(tester, Icons.timer),
          dark.toneColor(SwapTone.neutral),
        );
        expect(tester.getSize(find.byIcon(Icons.timer)), const Size.square(14));
        expect(
          tester.getTopLeft(find.text('Expires in 18s')).dx,
          tester.getTopRight(find.byIcon(Icons.timer)).dx + 6,
        );
      });

      for (final (name, media) in [
        ('plain text', swapDefaultMedia),
        ('bold text', bold),
      ]) {
        testWidgets('knows its one-line width before it is laid out, with '
            '$name', (tester) async {
          late double measured;
          await pumpSwapUi(
            tester,
            Center(
              child: Builder(
                builder: (context) {
                  measured = SwapBadge.widthOf(context, 'Best net return');
                  return const SwapBadge(label: 'Best net return');
                },
              ),
            ),
            media: media,
          );

          expect(
            measured,
            closeTo(tester.getSize(find.byType(SwapBadge)).width, 0.01),
          );
        });
      }
    });

    group('callout', () {
      test('each tone has its default icon', () {
        expect(
          {
            for (final tone in SwapTone.values)
              tone: SwapCallout.defaultIcon(tone),
          },
          {
            SwapTone.neutral: Icons.info_outline_rounded,
            SwapTone.brand: Icons.info_outline_rounded,
            SwapTone.success: Icons.verified_user_outlined,
            SwapTone.warning: Icons.warning_amber_rounded,
            SwapTone.pending: Icons.warning_amber_rounded,
            SwapTone.danger: Icons.error_outline_rounded,
            SwapTone.info: Icons.info_outline_rounded,
          },
        );
      });

      testWidgets('sets a title over the message, an action below', (
        tester,
      ) async {
        await pumpSwapUi(
          tester,
          const SwapCallout(
            title: 'Exact approval only',
            message: 'Gleec never asks for an unlimited permission.',
            tone: SwapTone.danger,
            action: Text('Learn more'),
          ),
        );

        final title = tester.getRect(find.text('Exact approval only'));
        final message = tester.getRect(
          find.text('Gleec never asks for an unlimited permission.'),
        );
        final action = tester.getRect(find.text('Learn more'));
        expect(message.top, title.bottom + 4);
        expect(action.top, message.bottom + 6);
        expect(iconColor(tester, Icons.error_outline_rounded), dark.danger);
        final decoration = decorationIn(tester, SwapCallout);
        expect(decoration.color, dark.dangerBg);
        expect(decoration.border, Border.all(color: dark.danger));
      });

      testWidgets('takes its own icon; speaks up only when asked', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await pumpSwapUi(
          tester,
          const Column(
            children: [
              SwapCallout(message: 'Quiet', icon: Icons.bolt),
              SwapCallout(message: 'Loud', liveRegion: true),
            ],
          ),
        );

        expect(iconColor(tester, Icons.bolt), dark.info);
        expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
        bool live(String text) => tester
            .getSemantics(find.text(text))
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion;
        expect(live('Quiet'), isFalse);
        expect(live('Loud'), isTrue);
        semantics.dispose();
      });
    });

    group('helper line', () {
      testWidgets('each tone has its colour and glyph', (tester) async {
        for (final (tone, color, glyph) in [
          (SwapTone.danger, dark.danger, Icons.error_outline_rounded),
          (SwapTone.warning, dark.warning, Icons.warning_amber_rounded),
          (SwapTone.pending, dark.warning, Icons.warning_amber_rounded),
          (SwapTone.neutral, dark.textSecondary, Icons.info_outline_rounded),
          (SwapTone.success, dark.textSecondary, Icons.info_outline_rounded),
        ]) {
          await pumpSwapUi(tester, SwapHelperLine(text: 'Note', tone: tone));
          expect(textColor(tester, 'Note'), color, reason: tone.name);
          expect(iconColor(tester, glyph), color, reason: tone.name);
        }
      });

      testWidgets('takes its own glyph and is announced as it changes', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await pumpSwapUi(
          tester,
          const SwapHelperLine(text: 'Max applied', icon: Icons.bolt),
        );

        expect(find.byIcon(Icons.bolt), findsOneWidget);
        expect(
          tester
              .getSemantics(find.text('Max applied'))
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        semantics.dispose();
      });
    });

    group('status hero', () {
      Color tileColor(WidgetTester tester) =>
          (tester
                      .widget<Container>(
                        find
                            .ancestor(
                              of: find.byType(Icon),
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;

      testWidgets('brand and neutral share the selected tile', (tester) async {
        for (final tone in [SwapTone.brand, SwapTone.neutral]) {
          await pumpSwapUi(
            tester,
            SwapStatusHero(
              icon: Icons.radar_rounded,
              title: 'Tracking',
              tone: tone,
            ),
          );
          expect(tileColor(tester), dark.selected);
          expect(iconColor(tester, Icons.radar_rounded), dark.brandHover);
        }
      });

      testWidgets('other tones take their own tile', (tester) async {
        await pumpSwapUi(
          tester,
          const SwapStatusHero(
            icon: Icons.undo_rounded,
            title: 'Refund received',
            tone: SwapTone.success,
          ),
        );

        expect(tileColor(tester), dark.successBg);
        expect(iconColor(tester, Icons.undo_rounded), dark.success);
      });

      testWidgets('heads with the title; body and action follow', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await pumpSwapUi(
          tester,
          const SwapStatusHero(
            icon: Icons.check,
            title: 'You received 3,001 USDC',
            body: 'Received on Ethereum.',
            action: Text('Start another'),
          ),
        );

        final title = tester.getRect(find.text('You received 3,001 USDC'));
        final body = tester.getRect(find.text('Received on Ethereum.'));
        expect(body.top, title.bottom + 8);
        expect(
          tester.getTopLeft(find.text('Start another')).dy,
          body.bottom + 16,
        );
        final data = tester
            .getSemantics(find.text('You received 3,001 USDC'))
            .getSemanticsData();
        expect(data.flagsCollection.isHeader, isTrue);
        semantics.dispose();
      });
    });

    group('question', () {
      testWidgets('upper-cases the eyebrow and stacks the answer', (
        tester,
      ) async {
        await pumpSwapUi(
          tester,
          const SwapQuestion(
            eyebrow: 'Where are the funds?',
            title: 'On Ethereum',
            body: 'Your balance is unchanged.',
            trailing: Text('Copy'),
          ),
        );

        final eyebrow = tester.getRect(find.text('WHERE ARE THE FUNDS?'));
        final title = tester.getRect(find.text('On Ethereum'));
        final body = tester.getRect(find.text('Your balance is unchanged.'));
        expect(title.top, eyebrow.bottom + 7);
        expect(body.top, title.bottom + 5);
        expect(tester.getTopLeft(find.text('Copy')).dy, body.bottom + 4);
        expect(
          decorationIn(tester, SwapQuestion).border,
          Border(top: BorderSide(color: dark.border)),
        );
      });

      testWidgets('can stand alone without a divider', (tester) async {
        await pumpSwapUi(
          tester,
          const SwapQuestion(eyebrow: 'What happened?', divider: false),
        );

        expect(find.text('WHAT HAPPENED?'), findsOneWidget);
        expect(decorationIn(tester, SwapQuestion).border, isNull);
      });
    });

    group('count dot', () {
      Future<(Color, Color?)> dotOf(
        WidgetTester tester,
        int count, {
        SwapTone? tone,
      }) async {
        await pumpSwapUi(
          tester,
          Center(
            child: SwapCountDot(count: count, tone: tone),
          ),
        );
        Finder inDot(Type type) => find.descendant(
          of: find.byType(SwapCountDot),
          matching: find.byType(type),
        );
        final box =
            tester.widget<Container>(inDot(Container)).decoration!
                as BoxDecoration;
        final text = tester.widget<Text>(inDot(Text));
        return (box.color!, text.style!.color);
      }

      testWidgets('counts up to 99, then says more', (tester) async {
        await dotOf(tester, 7);
        expect(find.text('7'), findsOneWidget);
        expect(
          tester.getSize(find.byType(SwapCountDot)).height,
          greaterThanOrEqualTo(20),
        );
        expect(
          tester.getSize(find.byType(SwapCountDot)).width,
          greaterThanOrEqualTo(20),
        );
        await dotOf(tester, 99);
        expect(find.text('99'), findsOneWidget);
        await dotOf(tester, 100);
        expect(find.text('99+'), findsOneWidget);
      });

      testWidgets('warning and danger dots read on the canvas colour', (
        tester,
      ) async {
        expect(await dotOf(tester, 2), (dark.brand, dark.onBrand));
        expect(await dotOf(tester, 2, tone: SwapTone.info), (
          dark.brand,
          dark.onBrand,
        ));
        expect(await dotOf(tester, 2, tone: SwapTone.warning), (
          dark.warning,
          dark.canvas,
        ));
        expect(await dotOf(tester, 2, tone: SwapTone.danger), (
          dark.danger,
          dark.canvas,
        ));
      });
    });
  });
}
