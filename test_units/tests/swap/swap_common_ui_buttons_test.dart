import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

import 'swap_common_ui_fakes.dart';

/// The swap surface's buttons: what each variant looks like, when it can be
/// pressed, and how a screen reader presses it.
void main() {
  const dark = SwapPalette.dark;

  group('swap buttons', () {
    useSwapUi();

    Material materialOf(WidgetTester tester, Type button) =>
        tester.widget<Material>(
          find
              .descendant(
                of: find.byType(button),
                matching: find.byType(Material),
              )
              .first,
        );

    Color borderOf(Material material) =>
        (material.shape! as RoundedRectangleBorder).side.color;

    group('full-width button', () {
      testWidgets('each variant has its colours', (tester) async {
        for (final (variant, background, foreground, border) in [
          (SwapButtonVariant.primary, dark.brand, dark.onBrand, dark.brand),
          (
            SwapButtonVariant.secondary,
            dark.surfaceHigh,
            dark.text,
            dark.controlBorder,
          ),
          (SwapButtonVariant.danger, dark.dangerBg, dark.danger, dark.danger),
        ]) {
          await pumpSwapUi(
            tester,
            SwapButton(label: 'Go', variant: variant, onPressed: () {}),
          );
          final material = materialOf(tester, SwapButton);
          expect(material.color, background, reason: variant.name);
          expect(material.textStyle!.color, foreground, reason: variant.name);
          expect(borderOf(material), border, reason: variant.name);
        }
      });

      testWidgets('is at least 52 tall and presses once per tap', (
        tester,
      ) async {
        var presses = 0;
        await pumpSwapUi(
          tester,
          SwapButton(label: 'Review swap', onPressed: () => presses++),
        );

        expect(tester.getSize(find.byType(SwapButton)).height, 52);
        await tester.tap(find.text('Review swap'));
        expect(presses, 1);
      });

      testWidgets('the primary button darkens while pressed', (tester) async {
        await pumpSwapUi(tester, SwapButton(label: 'Go', onPressed: () {}));

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(SwapButton)),
        );
        await tester.pump();
        expect(materialOf(tester, SwapButton).color, dark.brandPressed);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(materialOf(tester, SwapButton).color, dark.brand);
      });

      testWidgets('other variants keep their colour while pressed', (
        tester,
      ) async {
        await pumpSwapUi(
          tester,
          SwapButton(
            label: 'Go',
            variant: SwapButtonVariant.secondary,
            onPressed: () {},
          ),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(SwapButton)),
        );
        await tester.pump();
        expect(materialOf(tester, SwapButton).color, dark.surfaceHigh);
        await gesture.up();
      });

      testWidgets('without an action it is faded and inert', (tester) async {
        await pumpSwapUi(
          tester,
          const SwapButton(label: 'Go', onPressed: null),
        );

        final material = materialOf(tester, SwapButton);
        expect(material.color, dark.brand.withValues(alpha: 0.45));
        expect(material.textStyle!.color, dark.onBrand.withValues(alpha: 0.7));
        expect(borderOf(material), dark.brand.withValues(alpha: 0.4));
      });

      testWidgets('busy, it spins instead of its icon and cannot be pressed', (
        tester,
      ) async {
        var presses = 0;
        await pumpSwapUi(
          tester,
          SwapButton(
            label: 'Starting',
            icon: Icons.bolt,
            busy: true,
            onPressed: () => presses++,
          ),
          settle: false,
        );

        final spinner = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        );
        expect(spinner.color, dark.onBrand);
        expect(
          tester.getSize(find.byType(CircularProgressIndicator)),
          const Size.square(16),
        );
        expect(find.byIcon(Icons.bolt), findsNothing);
        expect(
          tester.widget<TextButton>(find.byType(TextButton)).onPressed,
          isNull,
        );
        await tester.tap(find.text('Starting'), warnIfMissed: false);
        expect(presses, 0);
      });

      testWidgets('an icon leads the label', (tester) async {
        await pumpSwapUi(
          tester,
          Center(
            child: SwapButton(
              label: 'Copy',
              icon: Icons.content_copy_rounded,
              onPressed: () {},
            ),
          ),
        );

        final icon = find.byIcon(Icons.content_copy_rounded);
        expect(tester.getSize(icon), const Size.square(18));
        expect(
          tester.getTopLeft(find.text('Copy')).dx,
          tester.getTopRight(icon).dx + 8,
        );
      });

      testWidgets('follows the light theme', (tester) async {
        await pumpSwapUi(
          tester,
          SwapButton(
            label: 'Go',
            variant: SwapButtonVariant.secondary,
            onPressed: () {},
          ),
          dark: false,
        );

        expect(
          materialOf(tester, SwapButton).textStyle!.color,
          SwapPalette.light.text,
        );
      });
    });

    group('link button', () {
      testWidgets('is a 48 dp target in the brand colour, icon first', (
        tester,
      ) async {
        var presses = 0;
        await pumpSwapUi(
          tester,
          Center(
            child: SwapLinkButton(
              label: 'Details',
              icon: Icons.info_outline,
              onPressed: () => presses++,
            ),
          ),
        );

        final size = tester.getSize(find.byType(SwapLinkButton));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(
          materialOf(tester, SwapLinkButton).textStyle!.color,
          dark.brandHover,
        );
        expect(
          tester.getSize(find.byIcon(Icons.info_outline)),
          const Size.square(16),
        );
        await tester.tap(find.text('Details'));
        expect(presses, 1);
      });

      testWidgets('without an action it cannot be pressed', (tester) async {
        await pumpSwapUi(
          tester,
          const SwapLinkButton(label: 'Details', onPressed: null),
        );

        expect(
          tester.widget<TextButton>(find.byType(TextButton)).onPressed,
          isNull,
        );
        expect(find.byType(Icon), findsNothing);
      });
    });

    group('icon button', () {
      testWidgets('is one labelled, pressable 48 dp button', (tester) async {
        final semantics = tester.ensureSemantics();
        var presses = 0;
        await pumpSwapUi(
          tester,
          Center(
            child: SwapIconButton(
              icon: Icons.close_rounded,
              label: 'Close',
              onPressed: () => presses++,
            ),
          ),
        );

        expect(
          tester.getSize(find.byType(SwapIconButton)),
          const Size.square(48),
        );
        expect(find.byTooltip('Close'), findsOneWidget);
        final node = tester.getSemantics(find.byType(SwapIconButton));
        final data = node.getSemanticsData();
        expect(data.label, 'Close');
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        tester.semantics.tap(find.semantics.byLabel('Close'));
        expect(presses, 1);
        await tester.tap(find.byType(SwapIconButton));
        expect(presses, 2);
        semantics.dispose();
      });

      testWidgets('without an action it reads as disabled', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpSwapUi(
          tester,
          const Center(
            child: SwapIconButton(
              icon: Icons.close_rounded,
              label: 'Close',
              onPressed: null,
            ),
          ),
        );

        final data = tester
            .getSemantics(find.byType(SwapIconButton))
            .getSemanticsData();
        expect(data.flagsCollection.isEnabled, Tristate.isFalse);
        expect(data.hasAction(SemanticsAction.tap), isFalse);
        semantics.dispose();
      });
    });
  });
}
