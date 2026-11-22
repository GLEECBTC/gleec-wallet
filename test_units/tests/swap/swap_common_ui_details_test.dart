import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

import 'swap_common_ui_fakes.dart';

enum _View { active, attention, completed }

/// Collapsible sections, label-value rows and filter chips.
void main() {
  const dark = SwapPalette.dark;

  group('swap detail widgets', () {
    useSwapUi();

    group('collapsible section', () {
      const section = SwapDetails(
        title: 'Costs & protection',
        children: [Text('Network fee')],
      );

      AnimatedRotation chevron(WidgetTester tester) =>
          tester.widget<AnimatedRotation>(find.byType(AnimatedRotation));

      bool? expandedFlag(WidgetTester tester) => tester
          .getSemantics(find.text('Costs & protection'))
          .getSemanticsData()
          .flagsCollection
          .isExpanded
          .toBoolOrNull();

      testWidgets('starts closed and opens on a tap, then closes again', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await pumpSwapUi(tester, section);

        expect(find.text('Network fee'), findsNothing);
        expect(chevron(tester).turns, 0);
        expect(expandedFlag(tester), isFalse);
        expect(
          tester.getSize(find.byType(InkWell)).height,
          greaterThanOrEqualTo(48),
        );

        await tester.tap(find.text('Costs & protection'));
        await tester.pumpAndSettle();
        expect(find.text('Network fee'), findsOneWidget);
        expect(chevron(tester).turns, 0.5);
        expect(expandedFlag(tester), isTrue);
        expect(
          tester.getTopLeft(find.text('Network fee')).dx -
              tester.getTopLeft(find.byType(SwapDetails)).dx,
          14,
        );

        await tester.tap(find.text('Costs & protection'));
        await tester.pumpAndSettle();
        expect(find.text('Network fee'), findsNothing);
        semantics.dispose();
      });

      testWidgets('can start open', (tester) async {
        await pumpSwapUi(
          tester,
          const SwapDetails(
            title: 'Route & identities',
            initiallyExpanded: true,
            children: [Text('Swap ID')],
          ),
        );

        expect(find.text('Swap ID'), findsOneWidget);
        expect(chevron(tester).turns, 0.5);
      });

      testWidgets('turns its chevron at once when less motion is asked for', (
        tester,
      ) async {
        await pumpSwapUi(tester, section);
        expect(chevron(tester).duration, const Duration(milliseconds: 180));

        await pumpSwapUi(
          tester,
          section,
          media: (
            textScale: 1,
            boldText: false,
            reduceMotion: true,
            announces: false,
          ),
        );
        expect(chevron(tester).duration, Duration.zero);
      });
    });

    group('detail row', () {
      const row = SwapDetailRow(
        label: 'Network fee',
        value: r'$3.20',
        valueColor: Color(0xFF00FF00),
      );

      testWidgets('sets the value beside its label when there is room', (
        tester,
      ) async {
        await pumpSwapUi(tester, const SizedBox(width: 400, child: row));

        final label = tester.getRect(find.text('Network fee'));
        final value = tester.getRect(find.text(r'$3.20'));
        expect(value.top, label.top);
        expect(value.left, label.right + 18);
        final text = tester.widget<Text>(find.text(r'$3.20'));
        expect(text.textAlign, TextAlign.right);
        expect(text.style!.color, const Color(0xFF00FF00));
        expect(text.style!.fontWeight, FontWeight.w700);
      });

      testWidgets('a short value sits flush with the right edge', (
        tester,
      ) async {
        await pumpSwapUi(tester, const SizedBox(width: 400, child: row));

        expect(tester.getRect(find.text(r'$3.20')).right, 400);
      });

      testWidgets('stacks the value under its label when narrow', (
        tester,
      ) async {
        await pumpSwapUi(
          tester,
          const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 300, child: row),
          ),
        );

        final label = tester.getRect(find.text('Network fee'));
        final value = tester.getRect(find.text(r'$3.20'));
        expect(value.left, label.left);
        expect(value.top, label.bottom + 2);
      });

      testWidgets('reads as one node, label then value', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpSwapUi(
          tester,
          const SwapDetailRow(label: 'Network fee', value: r'$3.20'),
        );

        expect(
          tester
              .getSemantics(find.text('Network fee'))
              .getSemanticsData()
              .label,
          'Network fee\n\$3.20',
        );
        expect(
          tester.widget<Text>(find.text(r'$3.20')).style!.color,
          dark.text,
        );
        semantics.dispose();
      });
    });

    group('filter bar', () {
      Widget bar(
        _View selected,
        ValueChanged<_View> onChanged, {
        int Function(_View)? countOf,
      }) => SwapFilterBar<_View>(
        values: _View.values,
        selected: selected,
        labelOf: (view) => switch (view) {
          _View.active => 'Active',
          _View.attention => 'Needs attention',
          _View.completed => 'Completed',
        },
        countOf: countOf,
        onChanged: onChanged,
        semanticLabel: 'Activity views',
      );

      Material chip(WidgetTester tester, String label) =>
          tester.widget<Material>(
            find
                .ancestor(of: find.text(label), matching: find.byType(Material))
                .first,
          );

      testWidgets('marks the selected chip and reports taps', (tester) async {
        final taps = <_View>[];
        await pumpSwapUi(tester, bar(_View.attention, taps.add));

        final selected = chip(tester, 'Needs attention');
        expect(selected.color, dark.selected);
        expect(
          (selected.shape! as RoundedRectangleBorder).side.color,
          dark.brand,
        );
        expect(
          tester.widget<Text>(find.text('Needs attention')).style!.color,
          dark.text,
        );
        final other = chip(tester, 'Active');
        expect(other.color, Colors.transparent);
        expect(
          (other.shape! as RoundedRectangleBorder).side.color,
          dark.controlBorder,
        );
        expect(
          tester.widget<Text>(find.text('Active')).style!.color,
          dark.textSecondary,
        );

        await tester.tap(find.text('Completed'));
        expect(taps, [_View.completed]);
        expect(
          tester.getSize(find.byType(InkWell).first).height,
          greaterThanOrEqualTo(48),
        );
      });

      testWidgets('shows a count only where there is one', (tester) async {
        await pumpSwapUi(
          tester,
          bar(
            _View.active,
            (_) {},
            countOf: (view) => view == _View.attention ? 3 : 0,
          ),
        );

        expect(find.byType(SwapCountDot), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(SwapCountDot)).dx,
          tester.getTopRight(find.text('Needs attention')).dx + 8,
        );
      });

      testWidgets('without counts, shows no dots', (tester) async {
        await pumpSwapUi(tester, bar(_View.active, (_) {}));

        expect(find.byType(SwapCountDot), findsNothing);
      });

      testWidgets('each chip is a button that says whether it is selected', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await pumpSwapUi(tester, bar(_View.completed, (_) {}));

        for (final (label, isSelected) in [
          ('Active', false),
          ('Completed', true),
        ]) {
          final flags = tester
              .getSemantics(find.text(label))
              .getSemanticsData()
              .flagsCollection;
          expect(flags.isButton, isTrue, reason: label);
          expect(flags.isSelected.toBoolOrNull(), isSelected, reason: label);
        }
        expect(find.bySemanticsLabel('Activity views'), findsOneWidget);
        semantics.dispose();
      });
    });
  });
}
