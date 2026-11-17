// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_amount_cards.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers what the form says and offers when nothing could be priced: each
/// kind of failure has its own words and its own next step.
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

  UnifiedSwapState failedWith(
    SwapQuoteFailure failure, {
    DateTime? rateLimitedUntil,
  }) => swapBaseForm().copyWith(
    evaluation: SwapEvaluationStatus.failed,
    failure: failure,
    failures: [failure],
    rateLimitedUntil: rateLimitedUntil,
  );

  Future<void> pump(
    WidgetTester tester,
    UnifiedSwapState state, {
    bool settle = true,
  }) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      const SwapEntryView(),
      bloc: swap,
      services: services,
      settle: settle,
    );
  }

  Future<void> press(WidgetTester tester) async {
    await tester.tap(swapPrimaryAction);
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester) =>
      swapButtonEnabled(tester, find.text(swapPrimaryLabel(tester)));

  SwapTone toneOf(WidgetTester tester, String text) => tester
      .widget<SwapHelperLine>(
        find.ancestor(
          of: find.text(text),
          matching: find.byType(SwapHelperLine),
        ),
      )
      .tone;

  group('a service error', () {
    testWidgets('keeps the selections and offers a retry', (tester) async {
      await pump(
        tester,
        failedWith(
          const SwapQuoteFailure(
            source: SwapLiquiditySource.routed,
            kind: SwapQuoteFailureKind.serviceError,
          ),
        ),
      );

      const message =
          "We couldn't check swap options. Your selections are preserved and "
          'nothing was signed or sent.';
      expect(find.text(message), findsOneWidget);
      expect(toneOf(tester, message), SwapTone.danger);
      expect(swapPrimaryLabel(tester), 'Try again');

      await press(tester);
      expect(swap.events, [const UnifiedSwapEvaluationRequested()]);
    });

    testWidgets('selling a token never invents a network-fee shortage', (
      tester,
    ) async {
      await pump(
        tester,
        failedWith(
          const SwapQuoteFailure(
            source: SwapLiquiditySource.routed,
            kind: SwapQuoteFailureKind.serviceError,
          ),
        ).copyWith(pay: usdc, receive: eth),
      );

      expect(
        find.text(
          "We couldn't check swap options. Your selections are preserved and "
          'nothing was signed or sent.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('keeps an unrelated gas balance out of the service error', (
      tester,
    ) async {
      final failed = failedWith(
        const SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.serviceError,
        ),
      ).copyWith(pay: usdc, receive: eth);

      await pump(tester, failed.copyWith(feeBalance: d('60')));
      expect(find.text('This address has 60 ETH.'), findsNothing);
      expect(find.textContaining('network fees'), findsNothing);

      await pump(tester, failed);
      expect(find.textContaining('This address has'), findsNothing);
    });
  });

  group('an inactive asset reported by a source', () {
    testWidgets('retries preparation through the bloc', (tester) async {
      await pump(
        tester,
        failedWith(
          SwapQuoteFailure(
            source: SwapLiquiditySource.atomic,
            kind: SwapQuoteFailureKind.assetInactive,
            asset: btc,
          ),
        ).copyWith(receive: btc),
      );

      expect(
        find.text('swapAssetPreparationUnavailable'.tr(args: ['BTC'])),
        findsOneWidget,
      );
      expect(swapPrimaryLabel(tester), 'Try again');
      await press(tester);
      expect(swap.events, [const UnifiedSwapPreparationRetried()]);
      expect(services.activations, isEmpty);
    });

    testWidgets('without naming one means the asset being paid', (
      tester,
    ) async {
      await pump(
        tester,
        failedWith(
          const SwapQuoteFailure(
            source: SwapLiquiditySource.routed,
            kind: SwapQuoteFailureKind.assetInactive,
          ),
        ),
      );

      expect(swapPrimaryLabel(tester), 'Try again');
      expect(
        find.text('swapAssetPreparationUnavailable'.tr(args: ['ETH'])),
        findsOneWidget,
      );
      await press(tester);
      expect(swap.events, [const UnifiedSwapPreparationRetried()]);
      expect(services.activations, isEmpty);
    });
  });

  testWidgets('an engine fault is offered again, its detail kept back', (
    tester,
  ) async {
    await pump(
      tester,
      failedWith(
        const SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.unknown,
          detail: 'MyAddressError: Cannot use ETH source address',
        ),
      ),
    );

    expect(
      find.text("We couldn't check swap options. Try again."),
      findsOneWidget,
    );
    expect(find.textContaining('MyAddressError'), findsNothing);
    expect(swapPrimaryLabel(tester), 'Try again');
    await press(tester);
    expect(swap.events, [const UnifiedSwapEvaluationRequested()]);
  });

  group('a rate limit', () {
    const rateLimited = SwapQuoteFailure(
      source: SwapLiquiditySource.routed,
      kind: SwapQuoteFailureKind.rateLimited,
    );
    const message =
        'Cross-network prices are paused while the price service limits '
        'requests. This can take up to two hours. Your selections are '
        'preserved.';

    testWidgets('is a warning, and holds the retry until the pause is over', (
      tester,
    ) async {
      await pump(
        tester,
        failedWith(rateLimited, rateLimitedUntil: DateTime(2100)),
      );

      expect(find.text(message), findsOneWidget);
      expect(toneOf(tester, message), SwapTone.warning);
      expect(swapPrimaryLabel(tester), 'Try again');
      expect(enabled(tester), isFalse);
    });

    testWidgets('once over, can be retried', (tester) async {
      await pump(
        tester,
        failedWith(rateLimited, rateLimitedUntil: DateTime(2000)),
      );

      expect(enabled(tester), isTrue);
      await press(tester);
      expect(swap.events, [const UnifiedSwapEvaluationRequested()]);
    });
  });

  group('an amount outside what a source accepts', () {
    testWidgets('gives the bound, and offers to use it', (tester) async {
      await pump(
        tester,
        failedWith(
          SwapQuoteFailure(
            source: SwapLiquiditySource.atomic,
            kind: SwapQuoteFailureKind.belowMinimum,
            minimum: d('0.5'),
          ),
        ),
      );

      expect(find.text('Minimum swap: 0.5 ETH'), findsOneWidget);
      expect(swapPrimaryLabel(tester), 'Use 0.5 ETH');
      await press(tester);
      expect(swap.events, [UnifiedSwapAmountSuggested(d('0.5'))]);
    });

    testWidgets('more than the balance is also named on the button', (
      tester,
    ) async {
      await pump(
        tester,
        failedWith(
          SwapQuoteFailure(
            source: SwapLiquiditySource.atomic,
            kind: SwapQuoteFailureKind.aboveMaximum,
            maximum: d('10'),
          ),
        ).copyWith(inputText: '12', issue: SwapFormIssue.insufficient),
      );

      expect(
        find.text('Only 2 ETH is spendable at this address.'),
        findsOneWidget,
      );
      expect(find.text('Maximum swap: 10 ETH'), findsOneWidget);
      expect(swapPrimaryLabel(tester), 'Not enough ETH');
      expect(enabled(tester), isFalse);
    });
  });

  testWidgets('no route keeps provider reasons behind Details', (tester) async {
    await pump(
      tester,
      failedWith(
        const SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.noRoute,
          reasons: ['Liquidity too low', 'Amount too small'],
        ),
      ),
    );

    expect(
      find.text('No swap is available for this amount and pair right now.'),
      findsOneWidget,
    );
    expect(
      find.text('Why: Liquidity too low · Amount too small'),
      findsNothing,
    );
    expect(swapPrimaryLabel(tester), 'Try again');
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(
      find.text('Why: Liquidity too low · Amount too small'),
      findsOneWidget,
    );
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(
      find.text('Why: Liquidity too low · Amount too small'),
      findsNothing,
    );
    expect(swapPrimaryLabel(tester), 'Try again');
  });

  testWidgets('long provider diagnostics do not crowd out a phone draft', (
    tester,
  ) async {
    final reason = List.filled(
      12,
      'No available quotes: provider minimum for '
      '8453-0x0000000000000000000000000000000000000000.',
    ).join(' ');
    final failed = failedWith(
      SwapQuoteFailure(
        source: SwapLiquiditySource.routed,
        kind: SwapQuoteFailureKind.noRoute,
        reasons: [reason],
      ),
    ).copyWith(pay: usdc, receive: eth, inputText: '0.000001');
    swap.emit(failed);
    await pumpSwapUi(
      tester,
      const SwapEntryView(),
      bloc: swap,
      services: services,
      size: const Size(390, 844),
    );

    final field = find.byKey(const Key('swap-amount'));
    expect(tester.widget<TextField>(field).controller!.text, '0.000001');
    expect(find.text('Why: $reason'), findsNothing);
    expect(
      find.text('No swap is available for this amount and pair right now.'),
      findsOneWidget,
    );
    expect(find.text('Details').hitTestable(), findsOneWidget);
    expect(swapPrimaryAction.hitTestable(), findsOneWidget);
    final actionTop = tester.getTopLeft(swapPrimaryAction).dy;
    for (final pill in find.byType(SwapAssetPill).evaluate()) {
      expect(
        tester.getRect(find.byWidget(pill.widget)).bottom,
        lessThan(actionTop),
      );
    }

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Why: $reason'), findsOneWidget);
    expect(swapPrimaryAction.hitTestable(), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, '0.000001');
    expect(tester.takeException(), isNull);

    // Polling the same attempt preserves the explicit expansion, while a
    // changed amount starts its diagnostic disclosure collapsed again.
    await emitSwapState(tester, swap, failed.copyWith(balance: d('3')));
    expect(find.text('Why: $reason'), findsOneWidget);
    await emitSwapState(tester, swap, failed.copyWith(inputText: '0.000002'));
    await tester.pumpAndSettle();
    expect(find.text('Why: $reason'), findsNothing);
    expect(tester.widget<TextField>(field).controller!.text, '0.000002');
    expect(swap.state.pay, usdc);
    expect(swap.state.receive, eth);
    expect(swapPrimaryLabel(tester), 'Try again');
    expect(swap.events, isEmpty);
  });

  testWidgets('a timeout says nothing was sent, and the amount is not wrong', (
    tester,
  ) async {
    await pump(
      tester,
      failedWith(
        const SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.timeout,
        ),
      ),
    );

    expect(
      find.text(
        'Checking options took too long. Your selections are preserved and '
        'nothing was signed or sent.',
      ),
      findsOneWidget,
    );
    final card = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.byKey(const Key('swap-amount')),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    expect(
      ((card.decoration! as BoxDecoration).border! as Border).top.color,
      SwapPalette.dark.controlBorder,
    );
  });
}
