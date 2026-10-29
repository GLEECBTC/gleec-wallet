import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';
import '../../support/legal_documents_fixture.dart';

import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers Max on a network's own coin when every route charges a provider
/// fee on top, paid in that coin with the gas, as Squid's gas receiver fee
/// is: what Max fills must pass the form's own check. Runs the real bloc,
/// repository and routed source over a scripted manager, with 2 ETH held,
/// 0.0005 ETH of gas and a 0.0012 ETH fee.
void main() {
  for (final expired in [false, true]) {
    test(
      'release reserve survives review and exact revalidation, expired=$expired',
      () {
        final executor = FakeExecutor(SwapLiquiditySource.routed);
        _run(nativeMaxGasReserve: true, executor: executor, (
          bloc,
          manager,
          async,
        ) {
          bloc.add(const UnifiedSwapMaxRequested());
          async.elapse(const Duration(seconds: 2));
          final maximum = bloc.state.maxApplied!;
          expect(maximum.amount, d('1.9966'));
          expect(maximum.reservedForFees, d('0.0022'));
          expect(bloc.state.selectedQuote!.fundingOnTopIn(eth), d('0.0017'));
          expect(bloc.state.canReview, isTrue);
          bloc.add(const UnifiedSwapReviewOpened());
          async.flushMicrotasks();
          final accepted = bloc.state.review!.quote;
          if (expired) async.elapse(SwapQuote.lifetime);
          bloc.add(const UnifiedSwapStartRequested());
          async.flushMicrotasks();
          expect(manager.maxCalls, 1);
          expect(manager.quotes.last.amount, accepted.sellAmount);
          expect(bloc.state.maxApplied, same(maximum));
          if (expired) {
            expect(executor.started, isEmpty);
            expect(bloc.state.review!.status, SwapReviewStatus.ready);
          } else {
            expect(executor.started.single.sellAmount, d('1.9966'));
            expect(
              executor.started.single.guaranteedReceive,
              accepted.guaranteedReceive,
            );
          }
        });
      },
    );
  }

  test('release Max refresh updates retained balance without charging it', () {
    _run(nativeMaxGasReserve: true, (bloc, manager, async) {
      bloc.add(const UnifiedSwapMaxRequested());
      async.elapse(const Duration(seconds: 2));
      async.elapse(const Duration(seconds: 16));
      manager.maximum = manager.respond!((
        from: eth,
        to: usdc,
        amount: d('1.9'),
        slippage: null,
        order: RoutedSwapOrder.cheapest,
      ));
      bloc.add(const UnifiedSwapEvaluationRequested(quiet: true));
      async.flushMicrotasks();
      expect(bloc.state.inputText, '1.8983');
      expect(bloc.state.maxApplied!.reservedForFees, d('0.0022'));
      expect(bloc.state.selectedQuote!.requiredGasBalance, d('0.0005'));
      bloc.add(const UnifiedSwapAmountChanged('0.5'));
      async.elapse(const Duration(seconds: 2));
      expect(bloc.state.maxRequested, isFalse);
      expect(bloc.state.selectedQuote!.maxRetainedBalance, isNull);
    });
  });

  test('Max uses a KDF quote instead of a recent route gas estimate', () {
    _run((bloc, manager, async) {
      bloc.add(const UnifiedSwapMaxRequested());
      async.elapse(const Duration(seconds: 3));

      expect(manager.maxCalls, 1);
      expect(bloc.state.inputText, '1.9983');
      expect(
        bloc.state.maxApplied!.reserveCovers,
        SwapMaxReserve.networkAndProviderFees,
      );
      expect(bloc.state.selectedQuote!.sellAmount, d('1.9983'));
      expect(bloc.state.issue, isNull);
      expect(bloc.state.canReview, isTrue);
    });
  });

  test('Max before the pair has a price fits the first time', () {
    _run(amount: '', (bloc, manager, async) {
      bloc.add(const UnifiedSwapMaxRequested());
      async.elapse(const Duration(seconds: 3));

      expect(manager.maxCalls, 1);
      expect(bloc.state.inputText, '1.9983');
      expect(
        bloc.state.maxApplied!.reserveCovers,
        SwapMaxReserve.networkAndProviderFees,
      );
      expect(bloc.state.issue, isNull);
      expect(bloc.state.canReview, isTrue);
    });
  });

  test('Max refresh replaces amount, minimum and funding as one snapshot', () {
    _run((bloc, manager, async) {
      bloc.add(const UnifiedSwapMaxRequested());
      async.elapse(const Duration(seconds: 2));
      async.elapse(const Duration(seconds: 16));
      manager.maximum = offerOf(
        sell: '1.9',
        guaranteed: '5700',
        expected: '5800',
        order: RoutedSwapOrder.cheapest,
        networkFees: [
          RoutedSwapNetworkFee(
            ticker: 'ETH',
            assetId: eth,
            amount: d('0.001'),
            requiredBalance: d('0.1'),
          ),
        ],
      );
      bloc.add(const UnifiedSwapEvaluationRequested(quiet: true));
      async.flushMicrotasks();
      expect(bloc.state.inputText, '1.9');
      expect(bloc.state.selectedQuote!.guaranteedReceive, d('5700'));
      expect(bloc.state.maxApplied!.reservedForFees, d('0.1'));
      expect(bloc.state.maxRequested, isTrue);
    });
  });

  test('manual input invalidates a late Max response and returns to exact', () {
    _run((bloc, manager, async) {
      manager.maxGate = Completer<RoutedSwapOffer>();
      bloc.add(const UnifiedSwapMaxRequested());
      async.flushMicrotasks();
      bloc.add(const UnifiedSwapAmountChanged('0.5'));
      async.elapse(const Duration(seconds: 1));
      manager.maxGate!.complete(offerOf(sell: '1.9'));
      async.flushMicrotasks();
      expect(bloc.state.inputText, '0.5');
      expect(bloc.state.maxRequested, isFalse);
      expect(bloc.state.selectedQuote!.sellAmount, d('0.5'));
    });
  });

  for (final expired in [false, true]) {
    test('Max survives review revalidation, expired=$expired', () {
      final executor = FakeExecutor(SwapLiquiditySource.routed);
      _run(executor: executor, (bloc, manager, async) {
        bloc.add(const UnifiedSwapMaxRequested());
        async.elapse(const Duration(seconds: 2));
        final maximum = bloc.state.maxApplied!;
        bloc.add(const UnifiedSwapReviewOpened());
        async.flushMicrotasks();
        final accepted = bloc.state.review!.quote;
        expect(bloc.state.maxRequested, isTrue);
        expect(bloc.state.maxApplied, same(maximum));

        if (expired) async.elapse(SwapQuote.lifetime);
        // A newly calculated Max would differ. Review must revalidate the
        // principal the user saw; init accepts only a concrete amount.
        manager.maximum = offerOf(sell: '1.9');
        final exactCalls = manager.quotes.length;
        bloc.add(const UnifiedSwapStartRequested());
        async.flushMicrotasks();

        expect(manager.maxCalls, 1);
        expect(manager.quotes.length, exactCalls + 1);
        expect(manager.quotes.last.amount, accepted.sellAmount);
        expect(bloc.state.maxRequested, isTrue);
        expect(bloc.state.maxApplied, same(maximum));
        if (expired) {
          expect(executor.started, isEmpty);
          expect(bloc.state.review!.quote.sellAmount, accepted.sellAmount);
          expect(bloc.state.review!.status, SwapReviewStatus.ready);
          // Returning to the form restores Max quoting, not exact mode.
          bloc.add(const UnifiedSwapReviewClosed());
          async.flushMicrotasks();
          expect(manager.maxCalls, 2);
          expect(bloc.state.inputText, '1.9');
          expect(bloc.state.maxRequested, isTrue);
        } else {
          expect(executor.started.single.sellAmount, accepted.sellAmount);
        }
      });
    });
  }

  test('Max review blocks a newly quoted funding shortfall before init', () {
    final executor = FakeExecutor(SwapLiquiditySource.routed);
    _run(executor: executor, (bloc, manager, async) {
      bloc.add(const UnifiedSwapMaxRequested());
      async.elapse(const Duration(seconds: 2));
      bloc.add(const UnifiedSwapReviewOpened());
      async.flushMicrotasks();
      final accepted = bloc.state.review!.quote;
      final respond = manager.respond!;
      manager.respond = (call) {
        final fresh = respond(call);
        return offerOf(
          from: call.from,
          to: call.to,
          sell: '${call.amount}',
          order: call.order,
          quotedAt: fresh.quotedAt,
          costs: fresh.costs,
          networkFees: [
            RoutedSwapNetworkFee(
              ticker: eth.id,
              assetId: eth,
              amount: d('0.0005'),
              requiredBalance: d('0.002'),
            ),
          ],
        );
      };
      bloc.add(const UnifiedSwapStartRequested());
      async.flushMicrotasks();

      expect(manager.maxCalls, 1);
      expect(manager.quotes.last.amount, accepted.sellAmount);
      expect(bloc.state.maxRequested, isTrue);
      expect(bloc.state.review!.status, SwapReviewStatus.revalidationFailed);
      expect(
        bloc.state.review!.revalidationFailure!.kind,
        SwapQuoteFailureKind.insufficientFunds,
      );
      expect(executor.started, isEmpty);
    });
  });

  test(
    'review freezes the accepted Max even when a refresh completes late',
    () {
      _run((bloc, manager, async) {
        bloc.add(const UnifiedSwapMaxRequested());
        async.elapse(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 16));
        manager.maxGate = Completer<RoutedSwapOffer>();
        bloc.add(const UnifiedSwapEvaluationRequested(quiet: true));
        async.flushMicrotasks();
        final accepted = bloc.state.selectedQuote!;
        bloc.add(const UnifiedSwapReviewOpened());
        async.flushMicrotasks();
        expect(bloc.state.view, UnifiedSwapView.review);
        manager.maxGate!.complete(offerOf(sell: '1.8', guaranteed: '5000'));
        async.flushMicrotasks();
        expect(bloc.state.review!.quote, same(accepted));
        expect(bloc.state.selectedQuote, same(accepted));
        expect(bloc.state.inputText, '1.9983');
      });
    },
  );

  test(
    'a rejected Max cannot be reviewed or silently quoted as full balance',
    () {
      _run((bloc, manager, async) {
        manager.maxError = const RoutedSwapInsufficientBalanceException(
          coin: 'ETH',
          available: '0.001',
          required: '0.01',
          lockedBySwaps: '1',
          message: 'short',
        );
        final exactCalls = manager.quotes.length;
        bloc.add(const UnifiedSwapMaxRequested());
        async.elapse(const Duration(seconds: 2));
        expect(bloc.state.evaluation, SwapEvaluationStatus.failed);
        expect(bloc.state.canReview, isFalse);
        expect(bloc.state.failure!.lockedBySwaps, d('1'));
        expect(manager.quotes.length, exactCalls);
        bloc.add(const UnifiedSwapEvaluationRequested());
        async.flushMicrotasks();
        expect(manager.maxCalls, 2);
        expect(manager.quotes.length, exactCalls);
      });
    },
  );

  test('Max preserves an already selected fastest route', () {
    _run((bloc, manager, async) {
      bloc.add(const UnifiedSwapAlternativesRequested());
      async.flushMicrotasks();
      final fastest = bloc.state.quotes!.options.firstWhere(
        (q) => q.order == SwapQuoteOrder.fastest,
      );
      bloc.add(UnifiedSwapOptionSelected(fastest.id));
      async.flushMicrotasks();
      manager.maximum = offerOf(
        sell: '1.95',
        order: RoutedSwapOrder.fastest,
        toolKey: 'fast',
      );
      bloc.add(const UnifiedSwapMaxRequested());
      async.elapse(const Duration(seconds: 2));
      expect(manager.maxOrders.last, RoutedSwapOrder.fastest);
      expect(bloc.state.inputText, '1.95');
      expect(bloc.state.selectedQuote!.order, SwapQuoteOrder.fastest);
      expect(bloc.state.manuallySelected, isTrue);
      expect(manager.quotes.last.amount, d('1.95'));
    });
  });

  test(
    'changing order in Max prices that order and compares at its amount',
    () {
      _run((bloc, manager, async) {
        bloc.add(const UnifiedSwapMaxRequested());
        async.elapse(const Duration(seconds: 2));
        bloc.add(const UnifiedSwapAlternativesRequested());
        async.flushMicrotasks();
        final fastest = bloc.state.quotes!.options.firstWhere(
          (q) => q.order == SwapQuoteOrder.fastest,
        );
        manager.maximum = offerOf(
          sell: '1.95',
          order: RoutedSwapOrder.fastest,
          toolKey: 'fast',
          guaranteed: '2900',
        );
        bloc.add(UnifiedSwapOptionSelected(fastest.id));
        async.elapse(const Duration(seconds: 1));
        expect(manager.maxOrders.last, RoutedSwapOrder.fastest);
        expect(bloc.state.inputText, '1.95');
        expect(bloc.state.selectedQuote!.order, SwapQuoteOrder.fastest);
        expect(manager.quotes.last.amount, d('1.95'));
      });
    },
  );
}

/// Opens the form on ETH -> USDC with [amount] and runs [script] on a fake
/// clock.
void _run(
  void Function(UnifiedSwapBloc bloc, SrcRoutedSwaps manager, FakeAsync async)
  script, {
  String amount = '1',
  bool nativeMaxGasReserve = false,
  FakeExecutor? executor,
}) {
  fakeAsync((async) {
    final start = DateTime(2026, 10, 5, 12);
    DateTime now() => start.add(async.elapsed);
    final manager = SrcRoutedSwaps()
      ..eligible = {eth, usdc}
      ..respond = (call) => offerOf(
        from: call.from,
        to: call.to,
        sell: '${call.amount}',
        order: call.order,
        toolKey: call.order == RoutedSwapOrder.fastest ? 'fast' : 'tool',
        costs: [
          RoutedSwapCost(
            label: 'Network fee',
            amount: d('0.0005'),
            kind: RoutedSwapCostKind.gas,
            isDeductedFromReceive: false,
            assetId: eth,
          ),
          RoutedSwapCost(
            label: 'Gas receiver fee',
            amount: d('0.0012'),
            kind: RoutedSwapCostKind.providerFee,
            isDeductedFromReceive: false,
            assetId: eth,
          ),
        ],
        networkFees: [
          RoutedSwapNetworkFee(
            ticker: eth.id,
            assetId: eth,
            amount: d('0.0005'),
            requiredBalance: d('0.0005'),
          ),
        ],
        quotedAt: now(),
      );
    manager.maximum = manager.respond!((
      from: eth,
      to: usdc,
      amount: d('1.9983'),
      slippage: null,
      order: RoutedSwapOrder.cheapest,
    ));
    final storage = MemoryStorage();
    final registry = SwapExecutionRegistry(
      executors: [executor ?? FakeExecutor(SwapLiquiditySource.routed)],
      inFlight: () async => const [],
    );
    final bloc =
        UnifiedSwapBloc(
            repository: UnifiedSwapRepository(
              sources: [
                RoutedSwapQuoteSource(
                  manager,
                  nativeMaxGasReserve: nativeMaxGasReserve,
                  networks: () => SwapNetworks([eth, usdc]),
                  now: now,
                ),
                FakeQuoteSource(
                  SwapLiquiditySource.atomic,
                  results: [
                    rejected(
                      SwapQuoteFailureKind.noRoute,
                      source: SwapLiquiditySource.atomic,
                    ),
                  ],
                ),
              ],
              pricing: SwapPricingService(
                FakePriceSource({eth: d('3000'), usdc: d('1')}),
              ),
              activatedAssets: () async => {eth, usdc},
            ),
            registry: registry,
            terms: SwapTermsRepository(
              legalDocuments: legalFixtureRepository(),
              walletKey: () async => 'w',
              storage: storage,
            ),
            preferences: SwapPreferences(
              walletKey: () async => 'w',
              storage: storage,
            ),
            spendableBalance: (asset) async =>
                asset == eth ? d('2') : d('5000'),
            addressOf: (asset) async => '0xaddress',
            resolveAsset: (ticker) => {eth.id: eth, usdc.id: usdc}[ticker],
            now: now,
          )
          ..add(const UnifiedSwapStarted())
          ..add(
            UnifiedSwapIntentApplied(
              pay: 'ETH',
              receive: 'USDC-ERC20',
              amount: amount,
            ),
          );
    async.elapse(const Duration(seconds: 2));
    script(bloc, manager, async);
    bloc.close();
    registry.dispose();
    async.flushMicrotasks();
  });
}
