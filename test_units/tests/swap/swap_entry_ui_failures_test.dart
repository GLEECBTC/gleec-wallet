// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
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

    testWidgets('selling a token suggests checking its network coin', (
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
          "We couldn't check swap options. If this keeps happening, check "
          'you have enough ETH on Ethereum for network fees.',
        ),
        findsOneWidget,
      );
    });
  });

  group('an inactive asset reported by a source', () {
    testWidgets('is activated from the button', (tester) async {
      services.activationGate = Completer<void>();
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
        find.text(
          "BTC isn't active in this wallet yet. Activate it to see its "
          'balance and prices.',
        ),
        findsOneWidget,
      );
      expect(swapPrimaryLabel(tester), 'Activate BTC');

      await tester.tap(swapPrimaryAction);
      await tester.pump();
      expect(swapPrimaryBusy(), isTrue);
      expect(enabled(tester), isFalse);

      services.activationGate!.complete();
      await tester.pumpAndSettle();
      expect(services.activations, [btc]);
      expect(swap.events, [UnifiedSwapAssetActivated(btc)]);
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

      expect(swapPrimaryLabel(tester), 'Activate ETH');
      await press(tester);
      expect(services.activations, [eth]);
    });
  });

  testWidgets('an address that cannot sign every step steers elsewhere', (
    tester,
  ) async {
    await pump(
      tester,
      failedWith(
        const SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.unsupportedSigner,
        ),
      ),
    );

    expect(
      find.text("This address can't sign every step required for this swap."),
      findsOneWidget,
    );
    expect(swapPrimaryLabel(tester), 'Choose another asset');
    await press(tester);
    expect(find.text('What you receive'), findsOneWidget);
  });

  group('a rate limit', () {
    const rateLimited = SwapQuoteFailure(
      source: SwapLiquiditySource.routed,
      kind: SwapQuoteFailureKind.rateLimited,
    );
    const message =
        "We're checking too often. Wait a moment, then try again. Your "
        'selections are preserved.';

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
    testWidgets('gives the bound, and leaves the amount to change', (
      tester,
    ) async {
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
      expect(swapPrimaryLabel(tester), 'Review swap');
      expect(enabled(tester), isFalse);
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

  testWidgets('no route explains why, in the provider\'s words', (
    tester,
  ) async {
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
      findsOneWidget,
    );
    expect(swapPrimaryLabel(tester), 'Try again');
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
