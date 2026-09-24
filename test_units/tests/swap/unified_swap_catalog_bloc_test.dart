import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_test_fixtures.dart';

/// Covers what the form knows before it asks for a price: which pairs can be
/// priced at all, which assets still need activating, and when a token can
/// never be priced because its network's own coin is missing.
void main() {
  final clock = DateTime(2026, 9, 24, 12);
  final gleecEvm = assetOf(
    'GLEEC',
    subClass: CoinSubClass.grc20,
    chainId: 11169,
  );
  final paxg = assetOf('PAXG-ERC20', parent: eth);
  final all = [eth, usdc, gleecEvm, paxg, btc];

  late FakeQuoteSource routed;
  late FakeQuoteSource atomic;
  late SwapExecutionRegistry registry;
  late MemoryStorage storage;
  late Map<AssetId, Decimal> balances;
  late Set<AssetId> activated;

  List<SwapQuoteResult> priced(SwapQuoteRequest request) => [
    SwapQuoteAvailable(
      quoteOf(
        id: 'routed',
        from: request.from,
        to: request.to,
        sell: request.amount.toString(),
        quotedAt: clock,
        pricing: const SwapQuotePricing(),
      ),
    ),
  ];

  UnifiedSwapBloc build() => UnifiedSwapBloc(
    repository: UnifiedSwapRepository(
      sources: [routed, atomic],
      pricing: SwapPricingService(
        FakePriceSource({eth: d('3000'), usdc: d('1')}),
      ),
      activatedAssets: () async => {...activated},
    ),
    registry: registry,
    terms: SwapTermsRepository(walletKey: () async => 'w', storage: storage),
    preferences: SwapPreferences(walletKey: () async => 'w', storage: storage),
    spendableBalance: (asset) async => balances[asset],
    addressOf: (asset) async => '0xaddress',
    resolveAsset: (ticker) => {for (final a in all) a.id: a}[ticker],
    now: () => clock,
    debounce: Duration.zero,
    evaluationTimeout: const Duration(seconds: 2),
    refreshInterval: const Duration(hours: 1),
    rateLimitPause: const Duration(milliseconds: 30),
  );

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await pumpEventQueue(times: 30);
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  Future<UnifiedSwapBloc> open(String pay, String receive) async {
    final bloc = build()
      ..add(const UnifiedSwapStarted())
      ..add(UnifiedSwapIntentApplied(pay: pay, receive: receive, amount: '1'));
    await settle();
    addTearDown(bloc.close);
    return bloc;
  }

  setUp(() {
    routed = FakeQuoteSource(
      SwapLiquiditySource.routed,
      tradable: {eth, usdc, paxg},
      respond: priced,
    );
    atomic = FakeQuoteSource(
      SwapLiquiditySource.atomic,
      tradable: {eth, usdc, gleecEvm, btc},
      results: [
        rejected(
          SwapQuoteFailureKind.noRoute,
          source: SwapLiquiditySource.atomic,
        ),
      ],
    );
    registry = SwapExecutionRegistry(
      executors: [
        FakeExecutor(SwapLiquiditySource.routed),
        FakeExecutor(SwapLiquiditySource.atomic),
      ],
      inFlight: () async => const [],
    );
    storage = MemoryStorage();
    balances = {eth: d('2'), usdc: d('500'), gleecEvm: d('10'), btc: d('1')};
    activated = {...all};
  });

  tearDown(() => registry.dispose());

  test('a pair no source trades explains itself and asks nobody', () async {
    final bloc = await open('GLEEC', 'PAXG-ERC20');

    expect(bloc.state.issue, SwapFormIssue.pairUnsupported);
    expect(bloc.state.pairSupport!.gap, SwapPairGap.sourcesDisjoint);
    expect(bloc.state.pairSupport!.limitingAsset, gleecEvm);
    expect(routed.requests, isEmpty);
    expect(atomic.requests, isEmpty);
  });

  test('an inactive asset waits until the user activates it', () async {
    activated = {usdc};
    routed.inactive = {eth};
    atomic.inactive = {eth};
    final bloc = await open('ETH', 'USDC-ERC20');

    expect(bloc.state.issue, SwapFormIssue.assetInactive);
    expect(bloc.state.inactiveAsset, eth);
    expect(routed.requests, isEmpty, reason: 'nothing priced while inactive');

    activated.add(eth);
    routed.inactive = {};
    atomic.inactive = {};
    bloc.add(UnifiedSwapAssetActivated(eth));
    await settle();

    expect(bloc.state.issue, isNull);
    expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
    expect(routed.requests, isNotEmpty);
  });

  test('a token is not priced without its network coin', () async {
    balances[eth] = Decimal.zero;
    final bloc = await open('USDC-ERC20', 'ETH');

    expect(bloc.state.issue, SwapFormIssue.noFeeBalance);
    expect(routed.requests, isEmpty);
    expect(atomic.requests, isEmpty);
  });

  test('every source\'s failure is kept for the copy', () async {
    routed
      ..respond = null
      ..results = [rejected(SwapQuoteFailureKind.serviceError)];
    final bloc = await open('ETH', 'USDC-ERC20');

    expect(bloc.state.evaluation, SwapEvaluationStatus.failed);
    expect(bloc.state.failure!.kind, SwapQuoteFailureKind.noRoute);
    expect(
      bloc.state.failures.map((f) => (f.source, f.kind)),
      containsAll([
        (SwapLiquiditySource.atomic, SwapQuoteFailureKind.noRoute),
        (SwapLiquiditySource.routed, SwapQuoteFailureKind.serviceError),
      ]),
    );
  });

  test('options keep the word about a source that could not answer', () async {
    atomic.results = [
      rejected(
        SwapQuoteFailureKind.serviceError,
        source: SwapLiquiditySource.atomic,
      ),
    ];
    final bloc = await open('ETH', 'USDC-ERC20');

    expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
    expect(bloc.state.failures.single.source, SwapLiquiditySource.atomic);
  });

  test('retrying an incomplete catalog reads it again', () async {
    routed.status = SwapCatalogStatus.stale;
    final bloc = await open('ETH', 'USDC-ERC20');
    expect(bloc.state.catalog.isIncomplete, isTrue);
    final reads = routed.assetsCalls;

    routed.status = SwapCatalogStatus.fresh;
    bloc.add(const UnifiedSwapCatalogRefreshRequested());
    await settle();

    expect(routed.assetsCalls, reads + 1);
    expect(bloc.state.catalog.isIncomplete, isFalse);
  });

  test('an asset activated elsewhere is picked up when chosen', () async {
    activated = {eth, usdc};
    atomic.inactive = {btc};
    final bloc = await open('ETH', 'USDC-ERC20');
    expect(bloc.state.catalog.isActive(btc), isFalse);

    activated.add(btc);
    atomic.inactive = {};
    bloc.add(UnifiedSwapReceiveAssetChanged(btc));
    await settle();

    expect(bloc.state.catalog.isActive(btc), isTrue);
    expect(bloc.state.issue, isNot(SwapFormIssue.assetInactive));
  });
}
