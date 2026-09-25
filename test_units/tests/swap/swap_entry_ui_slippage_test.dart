// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/views/swap/pickers/swap_slippage_sheet.dart';

import 'swap_entry_ui_fakes.dart';

/// Covers the slippage setting: it opens on the value in use, warns at
/// either end of the range, refuses what is not a number in range, and
/// sits beside or above its Change link as the space allows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpSwapUi();

  late RecordingSwapBloc swap;
  late FakeSwapServices services;

  setUp(() {
    swap = RecordingSwapBloc();
    services = FakeSwapServices();
  });

  tearDown(() => swap.close());

  final field = find.byType(TextField);

  Future<List<double>> pumpSheet(WidgetTester tester, double initial) async {
    final saved = <double>[];
    await pumpSwapUi(
      tester,
      SwapSlippageSheet(initial: initial, onSave: saved.add),
      bloc: swap,
      services: services,
    );
    return saved;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(field, text);
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the slippage in use, and saves through the bloc', (
    tester,
  ) async {
    swap.emit(swap.state.copyWith(slippage: 0.02));
    await pumpSwapUi(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showSwapSlippageSheet(context, swap),
          child: const Text('open'),
        ),
      ),
      bloc: swap,
      services: services,
    );
    await tapText(tester, 'open');

    expect(
      find.text(
        'How far a cross-network route may fill below the expected amount '
        'before it stops. Order-book swaps fill at the quoted price or not at '
        'all.',
      ),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.text('2%')),
      isSemantics(isButton: true, isSelected: true),
    );

    await tapText(tester, 'Use 2%');
    expect(swap.events, [const UnifiedSwapSlippageChanged(0.02)]);
    expect(tester.takeAnnouncements(), [
      isAccessibilityAnnouncement('Slippage set to 2%. Checking prices again.'),
    ]);
    expect(find.text('Use 2%'), findsNothing);
  });

  testWidgets('a value in between opens on Custom, filled in', (tester) async {
    final saved = await pumpSheet(tester, 0.003);

    expect(tester.widget<TextField>(field).controller!.text, '0.3');
    expect(find.textContaining('Above 1%'), findsNothing);
    expect(find.textContaining('Below 0.1%'), findsNothing);

    await tapText(tester, 'Use 0.3%');
    expect(saved.single, closeTo(0.003, 1e-12));
  });

  testWidgets('a very low custom value is warned about, but allowed', (
    tester,
  ) async {
    final saved = await pumpSheet(tester, 0.005);
    await tapText(tester, 'Custom');
    await type(tester, '0.05');

    expect(
      find.text(
        'Below 0.1%, cross-network routes stop more often when the price '
        'moves.',
      ),
      findsOneWidget,
    );
    await tapText(tester, 'Use 0.05%');
    expect(saved.single, closeTo(0.0005, 1e-12));
  });

  testWidgets('a value that is not a number cannot be saved', (tester) async {
    final saved = await pumpSheet(tester, 0.005);
    await tapText(tester, 'Custom');

    // Empty is not yet wrong, only unfinished.
    expect(find.text('Enter a value from 0.05% to 5%.'), findsNothing);
    expect(swapButtonEnabled(tester, find.text('Use this slippage')), isFalse);

    await type(tester, '.');
    expect(find.text('Enter a value from 0.05% to 5%.'), findsOneWidget);
    expect(swapButtonEnabled(tester, find.text('Use this slippage')), isFalse);

    await type(tester, '1,5');
    expect(find.text('Enter a value from 0.05% to 5%.'), findsNothing);
    expect(find.textContaining('Above 1%'), findsOneWidget);
    await tapText(tester, 'Use 1.5%');
    expect(saved.single, closeTo(0.015, 1e-12));
  });

  group('the summary', () {
    final change = find.text('Change');
    final title = find.text('Slippage · 1%');

    Future<int Function()> pumpSummary(
      WidgetTester tester, {
      Size size = const Size(420, 800),
      double textScale = 1,
    }) async {
      var changes = 0;
      await pumpSwapUi(
        tester,
        SwapSlippageSummary(slippage: 0.01, onChange: () => changes++),
        bloc: swap,
        services: services,
        size: size,
        textScale: textScale,
      );
      return () => changes;
    }

    testWidgets('says what the setting allows, with a way to change it', (
      tester,
    ) async {
      final changes = await pumpSummary(tester);

      expect(title, findsOneWidget);
      expect(
        find.text(
          'Cross-network routes may fill up to 1% below the expected amount. '
          'The minimum you receive already allows for it.',
        ),
        findsOneWidget,
      );
      expect(above(tester, title, change), isFalse);
      expect(
        tester.getTopLeft(change).dx,
        greaterThan(tester.getTopRight(title).dx),
      );

      await tester.tap(change);
      expect(changes(), 1);
    });

    for (final (name, size, scale) in [
      ('on a narrow screen', const Size(280, 800), 1.0),
      ('at 200% text', const Size(420, 1200), 2.0),
    ]) {
      testWidgets('puts the link under the summary $name', (tester) async {
        await pumpSummary(tester, size: size, textScale: scale);
        expect(above(tester, title, change), isTrue);
      });
    }
  });
}
