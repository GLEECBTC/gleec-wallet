// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/entry/swap_quote_strip.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the selected option in one line: the minimum, the cost and the
/// time, why it was chosen, how long it holds, and its rate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpSwapUi();

  late RecordingSwapBloc swap;
  late FakeSwapServices services;
  late DateTime clock;
  late int compared;

  setUp(() {
    swap = RecordingSwapBloc();
    services = FakeSwapServices();
    // When quoteOf's quotes are made; they hold for a minute.
    clock = DateTime(2026, 9, 24, 12);
    compared = 0;
  });

  tearDown(() => swap.close());

  Future<void> pump(
    WidgetTester tester,
    UnifiedSwapState state, {
    Size size = const Size(420, 1600),
    double textScale = 1,
    String? waitingFor,
  }) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      // Scrolling, as in the form: the strip is as tall as its content.
      SingleChildScrollView(
        child: BlocBuilder<UnifiedSwapBloc, UnifiedSwapState>(
          builder: (context, state) => SwapQuoteStrip(
            state: state,
            onCompare: () => compared++,
            now: () => clock,
            placeholder: waitingFor != null,
            waitingLabel: waitingFor,
          ),
        ),
      ),
      bloc: swap,
      services: services,
      size: size,
      textScale: textScale,
    );
  }

  final best = quoteOf(id: 'best');
  final runnerUp = quoteOf(
    id: 'runner-up',
    expected: '2990',
    guaranteed: '2975',
  );

  group('why the option was chosen', () {
    testWidgets('the best of comparable options says so, and what it means', (
      tester,
    ) async {
      await pump(tester, swapPricedForm(ranked: [best, runnerUp]));

      expect(find.text('Best net return'), findsOneWidget);
      expect(
        find.text('Among currently available, comparable options'),
        findsOneWidget,
      );
      expect(find.text('2,985 USDC'), findsOneWidget);
      expect(find.text(r'$3.00'), findsOneWidget);
      expect(find.text('About 45 sec'), findsOneWidget);
      expect(find.text('Compare options'), findsOneWidget);
    });

    testWidgets('another option chosen from a comparison is marked chosen', (
      tester,
    ) async {
      await pump(
        tester,
        swapPricedForm(ranked: [best, runnerUp], selectedId: 'runner-up'),
      );

      expect(find.text('Option selected'), findsOneWidget);
      expect(find.text('Best net return'), findsNothing);
      expect(find.text('2,975 USDC'), findsOneWidget);
    });

    testWidgets('the fastest route says it is the fastest', (tester) async {
      final fastest = quoteOf(
        id: 'fastest',
        order: SwapQuoteOrder.fastest,
        duration: const Duration(minutes: 3),
      );
      await pump(
        tester,
        swapPricedForm(ranked: [best, fastest], selectedId: 'fastest'),
      );

      expect(find.text('Fastest selected'), findsOneWidget);
      expect(find.text('About 3 minutes'), findsOneWidget);
    });

    testWidgets('an option picked by hand that cannot be compared is flagged', (
      tester,
    ) async {
      final unpriced = quoteOf(id: 'u', pricing: pricingOf(complete: false));
      await pump(
        tester,
        swapPricedForm(
          ranked: [],
          unrankable: [unpriced],
        ).copyWith(manuallySelected: true),
      );

      expect(find.text('Manually selected'), findsOneWidget);
      // No dollar price for its fee, so the fee itself is the cost.
      expect(find.text('0.001 ETH'), findsOneWidget);
    });

    testWidgets('fees with no dollar price are summed per token', (
      tester,
    ) async {
      final unpriced = quoteOf(
        id: 'u',
        fees: [
          for (final (asset, amount) in [
            (eth, '0.0003'),
            (gleec, '0.1'),
            (eth, '0.0001'),
          ])
            SwapFeeComponent(
              kind: SwapFeeKind.network,
              amount: d(amount),
              deductedFromReceive: false,
              asset: asset,
            ),
        ],
        pricing: pricingOf(network: null, complete: false),
      );
      await pump(tester, swapPricedForm(ranked: [], unrankable: [unpriced]));

      expect(find.text('0.0004 ETH + 0.1 GLEEC'), findsOneWidget);
    });

    testWidgets('fees that are not known at all are a dash, never a zero', (
      tester,
    ) async {
      final unknown = quoteOf(
        id: 'u',
        fees: const [],
        feesKnown: false,
        pricing: pricingOf(network: null, swap: null, complete: false),
      );
      await pump(tester, swapPricedForm(ranked: [], unrankable: [unknown]));

      expect(find.text('—'), findsOneWidget);
      expect(find.text(r'$0.00'), findsNothing);
    });

    testWidgets('a lone option is not badged at all', (tester) async {
      await pump(tester, swapPricedForm());

      for (final badge in [
        'Best net return',
        'Option selected',
        'Fastest selected',
        'Manually selected',
      ]) {
        expect(find.text(badge), findsNothing, reason: badge);
      }
    });
  });

  group('the link beside the badges', () {
    testWidgets('a lone order-book option offers its details', (tester) async {
      await pump(
        tester,
        swapPricedForm(
          ranked: [
            quoteOf(
              source: SwapLiquiditySource.atomic,
              routeKind: SwapRouteKind.direct,
              order: null,
            ),
          ],
        ),
      );

      expect(find.text('Compare options'), findsNothing);
      await tester.tap(find.text('Details'));
      expect(compared, 1);
    });

    testWidgets('a lone routed option still offers a comparison', (
      tester,
    ) async {
      await pump(tester, swapPricedForm());

      await tester.tap(find.text('Compare options'));
      expect(compared, 1);
    });
  });

  group('how long the option holds', () {
    testWidgets('an expired option says so rather than counting', (
      tester,
    ) async {
      clock = DateTime(2026, 9, 24, 12, 0, 50);
      await pump(
        tester,
        swapPricedForm(evaluation: SwapEvaluationStatus.expired),
      );

      expect(find.text('Quote expired'), findsOneWidget);
      expect(find.textContaining('Expires in'), findsNothing);
    });

    testWidgets('the last 20 seconds count down, a second at a time', (
      tester,
    ) async {
      clock = DateTime(2026, 9, 24, 12, 0, 30);
      await pump(tester, swapPricedForm());
      expect(find.textContaining('Expires in'), findsNothing);

      clock = DateTime(2026, 9, 24, 12, 0, 41);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Expires in 19s'), findsOneWidget);

      clock = DateTime(2026, 9, 24, 12, 0, 42);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Expires in 18s'), findsOneWidget);

      clock = DateTime(2026, 9, 24, 12, 1, 1);
      await pump(tester, swapPricedForm());
      expect(find.textContaining('Expires in'), findsNothing);
    });

    testWidgets('with no option chosen there is nothing to show or count', (
      tester,
    ) async {
      clock = DateTime(2026, 9, 24, 12, 0, 50);
      await pump(tester, swapPricedForm());
      expect(find.text('Expires in 10s'), findsOneWidget);

      await emitSwapState(tester, swap, swapBaseForm());
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Minimum received'), findsNothing);
      expect(find.textContaining('Expires in'), findsNothing);
    });
  });

  group('the layout', () {
    final minimum = find.text('Minimum received');
    final total = find.text('Total cost');

    testWidgets('puts the facts side by side where each has a line, the '
        'link beside the badges', (tester) async {
      await pump(
        tester,
        swapPricedForm(ranked: [best, runnerUp]),
        size: const Size(576, 1600),
      );

      expect(sameRow(tester, minimum, total), isTrue);
      expect(
        sameRow(
          tester,
          find.text('Best net return'),
          find.text('Compare options'),
        ),
        isFalse,
      );
      expect(
        tester.getTopLeft(find.text('Compare options')).dx,
        greaterThan(tester.getTopRight(find.text('Best net return')).dx),
      );
    });

    testWidgets('on a phone each fact has a row, its figure at the end edge', (
      tester,
    ) async {
      final slow = quoteOf(
        id: 'slow',
        guaranteed: '0.04397224',
        duration: const Duration(minutes: 12),
      );
      await pump(
        tester,
        swapPricedForm(ranked: [slow]),
        size: const Size(358, 1600),
      );

      final values = [
        find.text('0.04397 USDC'),
        find.text(r'$3.00'),
        find.text('About 12 minutes'),
      ];
      for (final (label, value) in [
        (minimum, values[0]),
        (total, values[1]),
        (find.text('Estimated time'), values[2]),
      ]) {
        // One line each, label and figure on it.
        expect(tester.getSize(label).height, lessThan(24));
        expect(tester.getSize(value).height, lessThan(24));
        expect(
          tester.getCenter(label).dy,
          closeTo(tester.getCenter(value).dy, 2),
        );
        expect(tester.getTopLeft(label).dx, tester.getTopLeft(minimum).dx);
        expect(tester.getTopRight(value).dx, tester.getTopRight(values[0]).dx);
      }
      expect(above(tester, minimum, total), isTrue);
    });

    for (final size in [const Size(358, 1600), const Size(576, 1600)]) {
      testWidgets('waiting, it has the shape its figures land in at '
          '${size.width.round()}', (tester) async {
        final orderBook = quoteOf(
          source: SwapLiquiditySource.atomic,
          routeKind: SwapRouteKind.direct,
          order: null,
        );
        await pump(
          tester,
          swapBaseForm().copyWith(evaluation: SwapEvaluationStatus.checking),
          size: size,
          waitingFor: 'Checking swap options…',
        );
        final strip = find.byType(SwapQuoteStrip);
        final waiting = tester.getRect(strip);
        final label = tester.getRect(minimum);
        expect(find.text('—'), findsNWidgets(3));
        expect(find.text('Checking swap options…'), findsOneWidget);

        await emitSwapState(tester, swap, swapPricedForm(ranked: [orderBook]));
        expect(find.text('—'), findsNothing);
        expect(tester.getRect(minimum), label);
        expect(tester.getRect(strip), waiting);

        // Its room is known before either: the form keeps it from the start.
        final reserved = SwapQuoteStrip.reservedHeight(
          tester.element(strip),
          width: size.width,
          receive: usdc,
          routed: false,
        );
        expect(reserved, greaterThanOrEqualTo(waiting.height));
        expect(reserved - waiting.height, lessThan(24));
      });
    }

    testWidgets('the room kept for a routed option holds its provider notice', (
      tester,
    ) async {
      for (final size in [const Size(328, 1600), const Size(576, 1600)]) {
        await pump(
          tester,
          swapPricedForm(ranked: [best, runnerUp]),
          size: size,
        );
        final strip = find.byType(SwapQuoteStrip);
        final reserved = SwapQuoteStrip.reservedHeight(
          tester.element(strip),
          width: size.width,
          receive: usdc,
          routed: true,
        );
        final shown = tester.getSize(strip).height;
        expect(reserved, greaterThanOrEqualTo(shown), reason: '$size');
        expect(reserved - shown, lessThan(8), reason: '$size');
      }
    });

    for (final (name, size, scale) in [
      ('on a narrow screen', const Size(300, 1600), 1.0),
      ('at 200% text', const Size(420, 2400), 2.0),
    ]) {
      testWidgets('stacks the facts and the link $name', (tester) async {
        await pump(
          tester,
          swapPricedForm(ranked: [best, runnerUp]),
          size: size,
          textScale: scale,
        );

        expect(above(tester, minimum, total), isTrue);
        expect(
          above(
            tester,
            find.text('Best net return'),
            find.text('Compare options'),
          ),
          isTrue,
        );
      });
    }
  });

  group('the rate', () {
    Future<void> pumpRate(WidgetTester tester, SwapQuote quote) => pumpSwapUi(
      tester,
      SwapRateLine(quote: quote),
      bloc: swap,
      services: services,
    );

    testWidgets('reads per unit paid, and flips round on tap', (tester) async {
      await pumpRate(tester, quoteOf());

      expect(find.text('1 ETH ≈ 3,000 USDC'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('1 ETH ≈ 3,000 USDC')),
        isSemantics(
          label: '1 ETH ≈ 3,000 USDC. Show inverse rate',
          isButton: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(find.text('1 ETH ≈ 3,000 USDC'));
      await tester.pump();
      expect(find.text('1 USDC ≈ 0.0003333 ETH'), findsOneWidget);

      await tester.tap(find.text('1 USDC ≈ 0.0003333 ETH'));
      await tester.pump();
      expect(find.text('1 ETH ≈ 3,000 USDC'), findsOneWidget);
    });

    testWidgets('is left out when there is no rate to give', (tester) async {
      await pumpRate(tester, quoteOf(expected: '0', guaranteed: '0'));
      expect(find.textContaining('≈'), findsNothing);

      await pumpRate(tester, quoteOf(sell: '0'));
      expect(find.textContaining('≈'), findsNothing);
    });
  });
}
