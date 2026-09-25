import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_test_fixtures.dart';

/// Runs [body] with a fresh [SwapBlocHarness] on a fake clock: no timer fires
/// until the test moves time on.
void swapBlocTest(
  String description,
  void Function(SwapBlocHarness h) body, {
  String? skip,
}) {
  test(description, skip: skip, () {
    fakeAsync((async) {
      final harness = SwapBlocHarness(async);
      try {
        body(harness);
      } finally {
        harness.dispose();
      }
    });
  });
}

/// A fee of [amount] [asset] that the balance pays, worth [usd].
SwapFeeComponent feeOf({
  String amount = '0.001',
  String? usd = '3',
  AssetId? asset,
  SwapFeeKind kind = SwapFeeKind.network,
}) => SwapFeeComponent(
  kind: kind,
  amount: d(amount),
  deductedFromReceive: false,
  asset: asset ?? eth,
  usdValue: usd == null ? null : d(usd),
);

/// The swap form over scripted sources, balances and storage.
///
/// The routed source prices every request at the current time; the order
/// book cannot trade anything unless a test says otherwise.
class SwapBlocHarness {
  SwapBlocHarness(this.async);

  final FakeAsync async;
  final DateTime start = DateTime(2026, 9, 24, 12);

  /// Wall-clock time that passed while no timer ran, as when a device sleeps.
  Duration skew = Duration.zero;

  DateTime now() => start.add(async.elapsed + skew);

  late final ScriptedQuoteSource routed = ScriptedQuoteSource(
    SwapLiquiditySource.routed,
    respond: priced,
  );
  late final ScriptedQuoteSource atomic = ScriptedQuoteSource(
    SwapLiquiditySource.atomic,
    results: [
      rejected(
        SwapQuoteFailureKind.pairUnsupported,
        source: SwapLiquiditySource.atomic,
      ),
    ],
  );
  final routedExecutor = GatedExecutor(SwapLiquiditySource.routed);
  final atomicExecutor = GatedExecutor(SwapLiquiditySource.atomic);
  late final registry = SwapExecutionRegistry(
    executors: [routedExecutor, atomicExecutor],
    inFlight: () async => const [],
  );
  final storage = MemoryStorage();
  final prices = FakePriceSource({eth: d('3000'), usdc: d('1')});
  final balances = <AssetId, Decimal>{
    eth: d('2'),
    usdc: d('5000'),
    btc: d('1'),
  };
  final unreadableBalances = <AssetId>{};
  final unreadableAddresses = <AssetId>{};
  List<SwapHolding> holdings = [];
  Object? holdingsError;
  Completer<void>? catalogGate;
  Completer<void>? holdingsGate;
  Completer<void>? termsGate;
  Completer<void>? balanceGate;
  final _blocs = <UnifiedSwapBloc>[];

  SwapPreferences get preferences =>
      SwapPreferences(walletKey: () async => 'wallet', storage: storage);

  SwapTermsRepository get terms =>
      SwapTermsRepository(walletKey: () async => 'wallet', storage: storage);

  /// A routed quote for [request], made now.
  List<SwapQuoteResult> priced(SwapQuoteRequest request) => [
    SwapQuoteAvailable(
      quoteOf(
        id: 'routed-${request.amount}',
        from: request.from,
        to: request.to,
        sell: request.amount.toString(),
        quotedAt: now(),
      ),
    ),
  ];

  UnifiedSwapBloc build({
    Duration debounce = Duration.zero,
    Duration refreshInterval = const Duration(seconds: 30),
    Duration idleLimit = const Duration(minutes: 5),
  }) {
    final bloc = UnifiedSwapBloc(
      repository: UnifiedSwapRepository(
        sources: [routed, atomic],
        pricing: SwapPricingService(prices),
        activatedAssets: () async {
          await catalogGate?.future;
          return {eth, usdc, btc, gleec};
        },
      ),
      registry: registry,
      terms: SwapTermsRepository(
        walletKey: () async {
          await termsGate?.future;
          return 'wallet';
        },
        storage: storage,
      ),
      preferences: preferences,
      spendableBalance: (asset) async {
        await balanceGate?.future;
        if (unreadableBalances.contains(asset)) throw StateError('offline');
        return balances[asset];
      },
      addressOf: (asset) async {
        if (unreadableAddresses.contains(asset)) throw StateError('offline');
        return 'address-of-${asset.id}';
      },
      resolveAsset: (ticker) => {
        for (final asset in [eth, usdc, btc, gleec]) asset.id: asset,
      }[ticker],
      holdings: () async {
        await holdingsGate?.future;
        final error = holdingsError;
        if (error != null) throw error;
        return holdings;
      },
      now: now,
      debounce: debounce,
      refreshInterval: refreshInterval,
      idleLimit: idleLimit,
    );
    _blocs.add(bloc);
    return bloc;
  }

  /// Opens the form on [pay] for [receive] and lets it price [amount].
  UnifiedSwapBloc open({
    String? pay = 'ETH',
    String? receive = 'USDC-ERC20',
    String? amount = '1',
    UnifiedSwapBloc? bloc,
  }) {
    final opened = (bloc ?? build())
      ..add(const UnifiedSwapStarted())
      ..add(
        UnifiedSwapIntentApplied(pay: pay, receive: receive, amount: amount),
      );
    settle();
    return opened;
  }

  /// [open], then the review of the preselected option.
  UnifiedSwapBloc inReview({UnifiedSwapBloc? bloc}) {
    final opened = open(bloc: bloc)..add(const UnifiedSwapReviewOpened());
    settle();
    return opened;
  }

  /// Runs everything that is due now, without moving the clock.
  void settle() => async.elapse(Duration.zero);

  void elapse(Duration duration) => async.elapse(duration);

  /// The value [future] completes with once pending work has run.
  T resolve<T>(Future<T> future) {
    final values = <T>[];
    unawaited(future.then(values.add));
    async.flushMicrotasks();
    expect(values, hasLength(1), reason: 'the future never completed');
    return values.single;
  }

  /// Every state [bloc] emits from now on.
  List<UnifiedSwapState> record(UnifiedSwapBloc bloc) {
    final states = <UnifiedSwapState>[];
    bloc.stream.listen(states.add);
    return states;
  }

  void dispose() {
    for (final bloc in _blocs) {
      unawaited(bloc.close());
    }
    unawaited(registry.dispose());
    async.flushMicrotasks();
  }
}

/// A [FakeQuoteSource] whose Max answer can be held back with [maxGate].
class ScriptedQuoteSource extends FakeQuoteSource {
  ScriptedQuoteSource(super.source, {super.respond, super.results});

  Completer<void>? maxGate;

  @override
  Future<SwapMaxAmount?> maxAmount({
    required AssetId from,
    required AssetId to,
    required Decimal balance,
  }) async {
    await maxGate?.future;
    return max;
  }
}

/// A [FakeExecutor] that holds each start until [gate] completes, when set.
class GatedExecutor extends FakeExecutor {
  GatedExecutor(super.source);

  Completer<void>? gate;

  @override
  Future<SwapExecutionHandle> start(SwapQuote quote) async {
    await gate?.future;
    return super.start(quote);
  }
}
