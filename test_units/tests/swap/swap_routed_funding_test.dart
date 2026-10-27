// The analyzer does not treat test_units as tests, so @visibleForTesting
// members read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
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

/// Covers the gas balance KDF requires before it sends a routed swap
/// (`required_balance`, KDF 35f0bde): the form checks it in place of the
/// estimated fee, and Max keeps it back, so what passes the form also passes
/// KDF's own check at start.
void main() {
  final networks = SwapNetworks([eth, usdc]);

  group('a routed quote', () {
    test('carries the gas balance KDF requires of the network coin', () {
      final quote = routedQuoteFromOffer(_ethOffer('1'), networks: networks);
      expect(quote.requiredGasBalance, d('0.0016'));
    });

    test('a token sell carries its network coin requirement', () {
      final quote = routedQuoteFromOffer(_usdcOffer(), networks: networks);
      expect(quote.requiredGasBalance, d('0.0016'));
    });

    test('carries none from an engine that reports none', () {
      final quote = routedQuoteFromOffer(
        _ethOffer('1', required: null),
        networks: networks,
      );
      expect(quote.requiredGasBalance, isNull);
    });

    test('funding counts the requirement in place of the estimated gas', () {
      final quote = routedQuoteFromOffer(_ethOffer('1'), networks: networks);
      // 0.0005 of gas and a 0.0012 fee on top, the gas counted at 0.0016.
      expect(quote.costOnTopIn(eth), d('0.0017'));
      expect(quote.fundingOnTopIn(eth), d('0.0028'));
      expect(quote.fundingOnTopIn(usdc), d('0'));
    });

    test('a token sell counts the requirement in the network coin', () {
      final quote = routedQuoteFromOffer(_usdcOffer(), networks: networks);
      expect(quote.fundingOnTopIn(eth), d('0.0016'));
      expect(quote.fundingOnTopIn(usdc), quote.costOnTopIn(usdc));
    });

    test('without a requirement, funding is the estimated cost', () {
      final quote = routedQuoteFromOffer(
        _ethOffer('1', required: null),
        networks: networks,
      );
      expect(quote.fundingOnTopIn(eth), quote.costOnTopIn(eth));
    });

    test('a GasEstimationFailed quote reads as a service error', () {
      final failure = RoutedSwapQuoteSource.failureFor(
        const RoutedSwapGasEstimationFailedException(
          coin: 'ETH',
          detail: 'Unable to estimate source-chain approval cost',
          message: 'Unable to estimate source-chain approval cost',
        ),
        from: usdc,
        to: eth,
      );
      expect(failure.kind, SwapQuoteFailureKind.serviceError);
      expect(failure.detail, startsWith('GasEstimationFailed'));
    });
  });

  group('the form', () {
    test('refuses an amount whose gas balance does not fit', () {
      // 1.9975 + 0.0005 + 0.0012 fits 2 ETH; with 0.0016 required it doesn't.
      _run(amount: '1.9975', (bloc, manager, async) {
        expect(bloc.state.selectedQuote!.sellAmount, d('1.9975'));
        expect(bloc.state.issue, SwapFormIssue.insufficient);
        expect(bloc.state.canReview, isFalse);
      });
    });

    test('accepts the same amount from an engine without a requirement', () {
      _run(amount: '1.9975', required: null, (bloc, manager, async) {
        expect(bloc.state.issue, isNull);
        expect(bloc.state.canReview, isTrue);
      });
    });

    test('Max uses KDF amount with the exact funding requirement', () {
      _run((bloc, manager, async) {
        manager.maximum = manager.respond!((
          from: eth,
          to: usdc,
          amount: d('1.9972'),
          slippage: null,
          order: RoutedSwapOrder.cheapest,
        ));
        bloc.add(const UnifiedSwapMaxRequested());
        async.elapse(const Duration(seconds: 3));

        // KDF leaves 0.0016 required gas plus 0.0012 provider fees.
        expect(manager.maxCalls, 1);
        expect(bloc.state.inputText, '1.9972');
        expect(bloc.state.maxApplied!.reservedForFees, d('0.0028'));
        expect(bloc.state.issue, isNull);
        expect(bloc.state.canReview, isTrue);
      });
    });

    test('Max uses KDF amount even without optional funding totals', () {
      _run(required: null, (bloc, manager, async) {
        manager.maximum = manager.respond!((
          from: eth,
          to: usdc,
          amount: d('1.9983'),
          slippage: null,
          order: RoutedSwapOrder.cheapest,
        ));
        bloc.add(const UnifiedSwapMaxRequested());
        async.elapse(const Duration(seconds: 3));

        expect(bloc.state.inputText, '1.9983');
        expect(bloc.state.issue, isNull);
      });
    });
  });
}

const String _required = '0.0016';

List<RoutedSwapCost> _ethCosts() => [
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
];

RoutedSwapNetworkFee _fee(String? required) => RoutedSwapNetworkFee(
  ticker: eth.id,
  assetId: eth,
  amount: d('0.0005'),
  requiredBalance: required == null ? null : d(required),
);

RoutedSwapOffer _ethOffer(
  String sell, {
  String? required = _required,
  DateTime? quotedAt,
}) => offerOf(
  from: eth,
  to: usdc,
  sell: sell,
  costs: _ethCosts(),
  networkFees: [_fee(required)],
  quotedAt: quotedAt,
);

RoutedSwapOffer _usdcOffer() => offerOf(
  from: usdc,
  to: eth,
  sell: '100',
  expected: '0.033',
  guaranteed: '0.032',
  costs: [_ethCosts().first],
  networkFees: [_fee(_required)],
);

/// Opens the form on ETH -> USDC with [amount], 2 ETH held, and runs
/// [script] on a fake clock. Every route has 0.0005 ETH of gas, KDF
/// requiring [required] for it, and a 0.0012 ETH provider fee on top.
void _run(
  void Function(UnifiedSwapBloc bloc, SrcRoutedSwaps manager, FakeAsync async)
  script, {
  String amount = '1',
  String? required = _required,
}) {
  fakeAsync((async) {
    final start = DateTime(2026, 10, 16, 12);
    DateTime now() => start.add(async.elapsed);
    final manager = SrcRoutedSwaps()
      ..eligible = {eth, usdc}
      ..respond = (call) =>
          _ethOffer('${call.amount}', required: required, quotedAt: now());
    final storage = MemoryStorage();
    final registry = SwapExecutionRegistry(
      executors: [FakeExecutor(SwapLiquiditySource.routed)],
      inFlight: () async => const [],
    );
    final bloc =
        UnifiedSwapBloc(
            repository: UnifiedSwapRepository(
              sources: [
                RoutedSwapQuoteSource(
                  manager,
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
              walletKey: () async => 'w',
              legalDocuments: legalFixtureRepository(),
              storage: storage,
            ),
            preferences: SwapPreferences(
              walletKey: () async => 'w',
              storage: storage,
            ),
            spendableBalance: (AssetId asset) async =>
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
