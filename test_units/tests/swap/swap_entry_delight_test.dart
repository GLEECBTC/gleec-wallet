// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_order_book_offers.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/views/swap/entry/swap_amount_cards.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/pickers/swap_asset_picker.dart';

import '../../support/legal_documents_fixture.dart';
import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

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

  Future<void> pump(
    WidgetTester tester,
    UnifiedSwapState state, {
    FakeTradingStatusBloc? policy,
    bool settle = true,
  }) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      const SwapEntryView(),
      bloc: swap,
      services: services,
      settle: settle,
      providers: [
        if (policy != null)
          BlocProvider<TradingStatusBloc>.value(value: policy),
      ],
    );
  }

  testWidgets('one useful quote can be reviewed while another source waits', (
    tester,
  ) async {
    await pump(tester, swapPricedForm().copyWith(quotesPending: true));

    expect(swapPrimaryLabel(tester), 'Review swap');
    expect(swapPrimaryBusy(), isFalse);
    expect(find.text('Checking other swap options…'), findsOneWidget);
    expect(find.text('Best net return'), findsNothing);
    await tester.tap(swapPrimaryAction);
    expect(swap.events, [const UnifiedSwapReviewOpened()]);
  });

  testWidgets('unfinished fiat decoration never claims a best return', (
    tester,
  ) async {
    await pump(
      tester,
      swapPricedForm(
        ranked: [
          quoteOf(),
          quoteOf(id: 'another'),
        ],
      ).copyWith(pricingPending: true),
    );
    expect(find.text('Best net return'), findsNothing);
    expect(swapPrimaryLabel(tester), 'Review swap');
  });

  testWidgets(
    'a better arriving option is offered without changing the amount shown',
    (tester) async {
      final first = quoteOf(
        id: 'first',
        expected: '2990',
        pricing: pricingOf(expected: '2990', minimum: '2980'),
      );
      final better = quoteOf(
        id: 'later',
        expected: '3010',
        pricing: pricingOf(expected: '3010', minimum: '3000'),
      );
      await pump(
        tester,
        swapPricedForm(ranked: [better, first], selectedId: first.id),
      );
      expect(find.text('2,990'), findsOneWidget);
      expect(find.text('Better option available'), findsOneWidget);
      expect(swap.events, isEmpty);
      await tester.tap(find.text('Better option available'));
      await tester.pumpAndSettle();
      expect(swap.events, [const UnifiedSwapAlternativesRequested()]);
    },
  );

  testWidgets(
    'desktop changed terms identify the preserved draft as previous',
    (tester) async {
      final original = quoteOf();
      final revised = quoteOf(
        id: 'updated',
        expected: '2950',
        guaranteed: '2935',
      );
      final changed = swapPricedForm(ranked: [original]).copyWith(
        view: UnifiedSwapView.review,
        review: SwapReview(
          legalSnapshot: legalFixtureSnapshot(),
          quote: revised,
          previous: original,
          status: SwapReviewStatus.materialUpdate,
        ),
      );
      swap.emit(changed);
      await pumpSwapUi(
        tester,
        const SwapEntryView(panelOpen: true),
        bloc: swap,
        services: services,
        size: const Size(1024, 1200),
      );
      expect(find.text('Previous estimate'), findsOneWidget);
      expect(find.text('3,000'), findsOneWidget);
      expect(find.text('2,950'), findsNothing);
      expect(swap.state.inputText, '1');
      expect(swap.events, isEmpty);

      await emitSwapState(tester, swap, swapPricedForm(ranked: [original]));
      expect(find.text('Previous estimate'), findsNothing);
      expect(find.text('You receive'), findsOneWidget);
      expect(find.text('3,000'), findsOneWidget);
    },
  );

  testWidgets('a slow quote keeps the cards and focus in place', (
    tester,
  ) async {
    final waiting = swapBaseForm().copyWith(
      evaluation: SwapEvaluationStatus.checking,
      quotesPending: true,
    );
    await pump(tester, waiting, settle: false);
    final field = find.byKey(const Key('swap-amount'));
    await tester.showKeyboard(field);
    await tester.pump();
    final pay = tester.getRect(find.byType(SwapPayCard));
    final receive = tester.getRect(find.byType(SwapReceiveCard));
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection.collapsed(offset: 0);
    final region = tester.getRect(find.byKey(const Key('swap-quote-region')));

    expect(find.text('swapEstimateUpdating'.tr()), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SwapReceiveCard),
        matching: find.text('0'),
      ),
      findsNothing,
    );
    expect(find.text('Still checking swap options…'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Still checking swap options…'), findsOneWidget);
    expect(tester.getRect(find.byType(SwapPayCard)), pay);
    expect(tester.getRect(find.byType(SwapReceiveCard)), receive);

    await emitSwapState(
      tester,
      swap,
      swapPricedForm().copyWith(quotesPending: true),
    );
    expect(find.text('3,000'), findsOneWidget);
    expect(tester.getRect(find.byType(SwapPayCard)), pay);
    expect(tester.getRect(find.byType(SwapReceiveCard)), receive);
    expect(tester.getRect(find.byKey(const Key('swap-quote-region'))), region);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(controller.selection, const TextSelection.collapsed(offset: 0));
  });

  testWidgets('a rejected quote stops waiting without moving the draft', (
    tester,
  ) async {
    services.prices[usdc] = d('1');
    final waiting = swapBaseForm(pay: usdc, receive: eth, input: '0.1')
        .copyWith(
          amountMode: SwapAmountMode.fiat,
          balance: d('0.4778'),
          evaluation: SwapEvaluationStatus.checking,
          quotesPending: true,
        );
    await pump(tester, waiting, settle: false);
    final field = find.byKey(const Key('swap-amount'));
    await tester.showKeyboard(field);
    await tester.pump();
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection.collapsed(offset: 1);
    final payRect = tester.getRect(find.byType(SwapPayCard));
    final receiveRect = tester.getRect(find.byType(SwapReceiveCard));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Still checking swap options…'), findsOneWidget);

    final failure = SwapQuoteFailure(
      source: SwapLiquiditySource.atomic,
      kind: SwapQuoteFailureKind.belowMinimum,
      minimum: d('5.8737'),
      offers: SwapOrderBookOffers([SwapOfferBand(d('5.8737'), d('100'))]),
    );
    await emitSwapState(
      tester,
      swap,
      waiting.copyWith(
        evaluation: SwapEvaluationStatus.failed,
        quotesPending: false,
        failure: failure,
        failures: [failure],
      ),
    );
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('swapEstimateUpdating'.tr()), findsNothing);
    expect(find.text('Still checking swap options…'), findsNothing);
    expect(find.text('Price estimate unavailable'), findsOneWidget);
    expect(
      find.text('The smallest offer right now takes 5.8737 USDC.'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SwapReceiveCard),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
    expect(tester.getRect(find.byType(SwapPayCard)), payRect);
    expect(tester.getRect(find.byType(SwapReceiveCard)), receiveRect);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(controller.text, '0.1');
    expect(controller.selection, const TextSelection.collapsed(offset: 1));
    expect(swap.state.pay, usdc);
    expect(swap.state.receive, eth);
    expect(
      swapButtonEnabled(tester, find.text(swapPrimaryLabel(tester))),
      isFalse,
    );
  });

  for (final kind in [
    SwapQuoteFailureKind.timeout,
    SwapQuoteFailureKind.noRoute,
    SwapQuoteFailureKind.rateLimited,
  ]) {
    testWidgets('${kind.name} does not leave the estimate updating', (
      tester,
    ) async {
      final failure = SwapQuoteFailure(
        source: SwapLiquiditySource.routed,
        kind: kind,
      );
      await pump(
        tester,
        swapBaseForm().copyWith(
          evaluation: SwapEvaluationStatus.failed,
          failure: failure,
          failures: [failure],
        ),
      );
      expect(find.text('swapEstimateUpdating'.tr()), findsNothing);
      expect(find.text('Price estimate unavailable'), findsOneWidget);
    });
  }

  for (final entry in {
    'failed preparation': swapBaseForm().copyWith(preparationFailedAsset: eth),
    'expired without a quote': swapBaseForm().copyWith(
      evaluation: SwapEvaluationStatus.expired,
    ),
    'zero after Max': swapBaseForm(input: '0')
        .copyWith(maxRequested: true, issue: SwapFormIssue.amountZero),
    'invalid amount': swapBaseForm(input: '.')
        .copyWith(issue: SwapFormIssue.amountMalformed),
  }.entries) {
    testWidgets('${entry.key} does not promise a pending estimate', (
      tester,
    ) async {
      await pump(tester, entry.value);
      expect(find.text('swapEstimateUpdating'.tr()), findsNothing);
      expect(find.text('Price estimate unavailable'), findsOneWidget);
    });
  }

  testWidgets('policy loading and failure never imply a location restriction', (
    tester,
  ) async {
    final policy = FakeTradingStatusBloc({});
    addTearDown(policy.close);
    final waiting = swapPricedForm().copyWith(
      tradingEnabled: false,
      tradingStatusLoading: true,
    );
    await pump(tester, waiting, policy: policy, settle: false);
    expect(swapPrimaryLabel(tester), 'Checking swap availability…');
    expect(find.textContaining('location'), findsNothing);

    await emitSwapState(
      tester,
      swap,
      waiting.copyWith(
        tradingStatusLoading: false,
        tradingStatusUnavailable: true,
      ),
    );
    expect(find.text('swapAvailabilityUnavailable'.tr()), findsOneWidget);
    expect(find.textContaining('location'), findsNothing);
    expect(swapPrimaryLabel(tester), 'Try again');
    await tester.tap(swapPrimaryAction);
    expect(policy.events, [isA<TradingStatusCheckRequested>()]);
  });

  testWidgets('unknown funding cannot enable review or invent a shortage', (
    tester,
  ) async {
    await pump(
      tester,
      swapPricedForm().copyWith(clearBalance: true),
      settle: false,
    );
    expect(swapPrimaryLabel(tester), 'Checking available balance…');
    expect(find.textContaining('Not enough'), findsNothing);
    expect(find.textContaining('Balance'), findsNothing);
    await tester.tap(swapPrimaryAction);
    expect(swap.events, isEmpty);
  });

  testWidgets(
    'the reference phone keeps both identities and receipt above the keyboard',
    (tester) async {
      swap.emit(swapPricedForm());
      await pumpSwapUi(
        tester,
        const SwapEntryView(),
        bloc: swap,
        services: services,
        size: const Size(390, 844),
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.showKeyboard(find.byKey(const Key('swap-amount')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      await tester.pumpAndSettle();
      final actionTop = tester.getTopLeft(swapPrimaryAction).dy;
      for (final pill in find.byType(SwapAssetPill).evaluate()) {
        expect(
          tester.getRect(find.byWidget(pill.widget)).bottom,
          lessThan(actionTop),
        );
      }
      expect(tester.getRect(find.text('3,000')).bottom, lessThan(actionTop));
      expect(swapPrimaryAction.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a quote highlight ends on background and never replays on resume',
    (tester) async {
      await pump(
        tester,
        swapBaseForm().copyWith(evaluation: SwapEvaluationStatus.checking),
        settle: false,
      );
      final region = find.byKey(const Key('swap-quote-region'));
      Color color() =>
          (tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: region,
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .color!;
      await emitSwapState(tester, swap, swapPricedForm());
      expect(color().a, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(color().a, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(color().a, 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(color().a, 0);
    },
  );

  testWidgets('network filtering retains the exact selected asset identity', (
    tester,
  ) async {
    final arbitrum = assetOf(
      'ETH-ARB20',
      subClass: CoinSubClass.arbitrum,
      chainId: 42161,
    );
    final usdcArbitrum = assetOf(
      'USDC-ARB20',
      parent: arbitrum,
      subClass: CoinSubClass.arbitrum,
      chainId: 42161,
    );
    services
      ..known = [eth, usdc, arbitrum, usdcArbitrum]
      ..activated = {eth, usdc, arbitrum, usdcArbitrum}
      ..balances = {eth: d('1')};
    final popped = await openSwapRoute(
      tester,
      SwapAssetPicker(
        side: SwapPickerSide.receive,
        catalog: SwapCatalog(
          sources: [
            SwapSourceAssets(
              source: SwapLiquiditySource.routed,
              quotable: services.activated,
            ),
          ],
        ),
        selected: null,
        other: null,
        services: services,
        isBlocked: (_) => false,
      ),
      bloc: swap,
      services: services,
    );
    expect(
      tester.getSemantics(find.text('Popular')),
      isSemantics(isSelected: true),
    );
    await tester.tap(find.byKey(const Key('swap-picker-network')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arbitrum').last);
    await tester.pumpAndSettle();
    expect(find.text('USDC'), findsOneWidget);
    await tester.tap(find.text('USDC'));
    await tester.pumpAndSettle();
    expect(popped, [usdcArbitrum]);
    expect(services.activations, isEmpty);
  });
}
