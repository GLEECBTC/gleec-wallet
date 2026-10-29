import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

import 'swap_common_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Token icons, copyable values and loading placeholders.
void main() {
  const dark = SwapPalette.dark;
  const reduced = (
    textScale: 1.0,
    boldText: false,
    reduceMotion: true,
    announces: false,
  );

  group('swap content widgets', () {
    useSwapUi();

    group('token icon', () {
      testWidgets('a wallet asset shows its logo, silently', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpSwapUi(
          tester,
          Center(child: SwapTokenIcon(asset: eth, size: 40)),
          settle: false,
        );

        expect(
          tester.getSize(find.byType(SwapTokenIcon)),
          const Size.square(40),
        );
        expect(tester.widget<AssetLogo>(find.byType(AssetLogo)).size, 40);
        expect(
          find.descendant(
            of: find.byType(SwapTokenIcon),
            matching: find.byType(ExcludeSemantics),
          ),
          findsOneWidget,
        );
        semantics.dispose();
      });

      testWidgets('an unknown asset shows its ticker, at most three letters', (
        tester,
      ) async {
        for (final (ticker, shown) in [
          ('usdc', 'USD'),
          ('BTC', 'BTC'),
          (' eth ', 'ETH'),
          (null, '?'),
        ]) {
          await pumpSwapUi(
            tester,
            Center(child: SwapTokenIcon(ticker: ticker)),
          );
          expect(find.text(shown), findsOneWidget, reason: '$ticker');
        }
      });

      testWidgets('the monogram is a circle sized to the icon', (tester) async {
        await pumpSwapUi(
          tester,
          const Center(child: SwapTokenIcon(ticker: 'XYZ', size: 48)),
        );

        expect(
          tester.getSize(find.byType(SwapTokenIcon)),
          const Size.square(48),
        );
        final text = tester.widget<Text>(find.text('XYZ'));
        expect(text.style!.fontSize, closeTo(14.4, 0.001));
        expect(text.style!.color, dark.text);
        final circle =
            tester
                    .widget<Container>(
                      find.descendant(
                        of: find.byType(SwapTokenIcon),
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration!
                as BoxDecoration;
        expect(circle.shape, BoxShape.circle);
        expect(circle.color, dark.surfaceHighest);
      });
    });

    group('copy line', () {
      late List<String> copied;

      setUp(() {
        copied = [];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                copied.add((call.arguments as Map)['text'] as String);
              }
              return null;
            });
      });

      tearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      Future<void> dismissSnackBar(WidgetTester tester) async {
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
      }

      testWidgets('copies the full value and says what was copied', (
        tester,
      ) async {
        await pumpSwapUi(
          tester,
          const SwapCopyLine(value: swapAddress, label: 'Address'),
        );

        expect(find.text(swapAddress), findsOneWidget);
        await tester.tap(find.text('Copy'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(copied, [swapAddress]);
        expect(find.text('Address copied'), findsOneWidget);
        await dismissSnackBar(tester);
      });

      testWidgets('without a label it names the value itself', (tester) async {
        await pumpSwapUi(
          tester,
          const SwapCopyLine(value: 'swap-1', copyLabel: 'Copy ID'),
        );

        await tester.tap(find.text('Copy ID'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(copied, ['swap-1']);
        expect(find.text('swap-1 copied'), findsOneWidget);
        await dismissSnackBar(tester);
      });

      testWidgets('reads as one labelled value in monospace', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpSwapUi(
          tester,
          const Column(
            children: [
              SwapCopyLine(value: swapAddress, label: 'Address'),
              SwapCopyLine(value: 'swap-1'),
            ],
          ),
        );

        expect(find.bySemanticsLabel('Address: $swapAddress'), findsOneWidget);
        expect(find.bySemanticsLabel('swap-1'), findsOneWidget);
        final text = tester.widget<SelectableText>(
          find.byType(SelectableText).first,
        );
        expect(text.style!.fontFamily, 'monospace');
        expect(text.style!.color, dark.text);
        semantics.dispose();
      });
    });

    group('skeleton', () {
      LinearGradient gradientOf(WidgetTester tester) =>
          (tester
                          .widget<Container>(
                            find.descendant(
                              of: find.byType(SwapSkeleton),
                              matching: find.byType(Container),
                            ),
                          )
                          .decoration!
                      as BoxDecoration)
                  .gradient!
              as LinearGradient;

      testWidgets('shimmers across its surface colours', (tester) async {
        await pumpSwapUi(
          tester,
          const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 200, child: SwapSkeleton(widthFactor: 0.5)),
          ),
          settle: false,
        );

        expect(
          tester.getSize(
            find.descendant(
              of: find.byType(SwapSkeleton),
              matching: find.byType(Container),
            ),
          ),
          const Size(100, 18),
        );
        final start = gradientOf(tester);
        expect(start.colors, [
          dark.surfaceHigh,
          dark.surfaceHighest,
          dark.surfaceHigh,
        ]);
        await tester.pump(const Duration(milliseconds: 700));
        expect(gradientOf(tester).begin, isNot(start.begin));
        expect(tester.hasRunningAnimations, isTrue);
      });

      testWidgets('stands still when less motion is asked for', (tester) async {
        await pumpSwapUi(
          tester,
          const SwapSkeleton(height: 24),
          media: reduced,
          settle: false,
        );

        final start = gradientOf(tester).begin;
        await tester.pump(const Duration(milliseconds: 700));
        expect(gradientOf(tester).begin, start);
        expect(tester.hasRunningAnimations, isFalse);
        expect(tester.getSize(find.byType(SwapSkeleton)).height, 24);
      });

      testWidgets('stops and restarts as the setting changes', (tester) async {
        await pumpSwapUi(tester, const SwapSkeleton(), settle: false);
        expect(tester.hasRunningAnimations, isTrue);

        await pumpSwapUi(
          tester,
          const SwapSkeleton(),
          media: reduced,
          settle: false,
        );
        final still = gradientOf(tester).begin;
        await tester.pump(const Duration(milliseconds: 700));
        expect(gradientOf(tester).begin, still);
        expect(tester.hasRunningAnimations, isFalse);

        await pumpSwapUi(tester, const SwapSkeleton(), settle: false);
        expect(tester.hasRunningAnimations, isTrue);
      });
    });
  });
}
