// The analyzer does not treat test_units as tests, so @visibleForTesting
// members read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

const _tick = Duration(milliseconds: 1);

/// The form's 25 s for one price: all the order book has for Max when
/// another source could answer instead.
const _budget = Duration(seconds: 25);

/// A Max asked of the repository, as it stands so far.
class _AskedMax {
  Map<SwapLiquiditySource, SwapMaxAmount>? maxes;
  SwapQuoteFailure? failure;
}

/// Covers Max on the order book when the coin sold also pays the gas to claim
/// what arrives, as for a token on its own network, and when KDF's own Max
/// is slow or never comes.
void main() {
  final usdt = assetOf('USDT-ERC20', parent: eth);
  late SrcTrading trading;

  setUp(
    () => trading = SrcTrading()
      ..maxTaker = '0.98'
      ..bids = [bidOf('3000', '0.01', '5')]
      ..preimage = preimageOf(relCoinFee: coinFeeOf('ETH', '0.002')),
  );

  Future<SwapMaxAmount?> maxOf({
    AssetId? from,
    AssetId? to,
    DateTime Function()? now,
  }) => AtomicSwapQuoteSource(
    trading: trading,
    networks: () => SwapNetworks([eth, btc]),
    now: now,
  ).maxAmount(from: from ?? eth, to: to ?? usdc, balance: d('1'));

  /// Max on 1 ETH sold for USDC, through the repository: the order book over
  /// [trading] beside an aggregator answering [routed], or that cannot tell.
  /// [alone] keeps the aggregator from the pair, as for GLEEC, leaving the
  /// order book the only source. Read the answer, or the failure, as it
  /// stands.
  _AskedMax askMax(
    FakeAsync async, {
    SwapMaxAmount? routed,
    SwapLiquiditySource? preferred,
    bool alone = false,
  }) {
    final start = DateTime(2026, 10, 5);
    final repository = UnifiedSwapRepository(
      sources: [
        FakeQuoteSource(
          SwapLiquiditySource.routed,
          tradable: alone ? {eth} : {eth, usdc},
          max: routed,
        ),
        AtomicSwapQuoteSource(
          trading: trading,
          networks: () => SwapNetworks([eth, btc]),
          now: () => start.add(async.elapsed),
        ),
      ],
      pricing: SwapPricingService(FakePriceSource({})),
      activatedAssets: () async => {eth, usdc},
    );
    final asked = _AskedMax();
    unawaited(
      repository
          .catalog()
          .then(
            (_) => repository.maxAmounts(
              from: eth,
              to: usdc,
              balance: d('1'),
              preferred: preferred,
            ),
          )
          .then<void>(
            (maxes) {
              asked.maxes = maxes;
            },
            onError: (Object error) {
              asked.failure = (error as SwapMaxUnavailableException).failure;
            },
          ),
    );
    async.flushMicrotasks();
    return asked;
  }

  test('keeps back the gas to claim a token on its network', () async {
    expect(
      await maxOf(),
      SwapMaxAmount(
        amount: d('0.978'),
        reservedForFees: d('0.022'),
        feeAsset: eth,
        reserveCovers: SwapMaxReserve.tradingAndNetworkFees,
        coversRefund: true,
      ),
    );
  });

  test('reads the claim at KDF\'s Max, for the least KDF receives', () async {
    trading.minimum = '0.01';

    await maxOf();

    // 0.01 / 0.98, rounded up so the order still receives the minimum.
    expect(trading.preimages.single, (
      volume: '0.98',
      price: '0.010204081632653062',
      method: SwapMethod.sell,
    ));
  });

  test('a claim the coin sold does not pay is left to KDF', () async {
    trading.preimage = preimageOf(
      relCoinFee: coinFeeOf('ETH', '0.002', fromVolume: true),
    );
    final fromVolume = await maxOf();
    trading.preimage = preimageOf(relCoinFee: coinFeeOf('BNB', '0.002'));
    final otherCoin = await maxOf();
    trading.preimage = preimageOf();
    final unreported = await maxOf();

    for (final max in [fromVolume, otherCoin, unreported]) {
      expect(max!.amount, d('0.98'));
    }
  });

  test('reads no preimage for a claim paid in another coin', () async {
    final forBtc = await maxOf(to: btc);
    final fromToken = await maxOf(from: usdc, to: eth);
    final betweenTokens = await maxOf(from: usdc, to: usdt);

    expect(trading.preimages, isEmpty);
    for (final max in [forBtc, fromToken, betweenTokens]) {
      expect(max!.amount, d('0.98'));
    }
  });

  test('reads the claim with no offers, or no book, to go by', () async {
    trading.bids = [];
    final empty = await maxOf();
    trading.bids = [bidOf('3000', '0.01', '5', mine: true)];
    final onlyMine = await maxOf();
    trading.bookError = StateError('orderbook offline');
    final unread = await maxOf();

    expect(trading.preimages, hasLength(3));
    for (final max in [empty, onlyMine, unread]) {
      expect(max!.amount, d('0.978'));
      expect(max.reservedForFees, d('0.022'));
    }
  });

  test('a claim that cannot be read leaves KDF\'s Max', () async {
    trading.preimageError = StateError('preimage failed');
    final failed = await maxOf();
    trading
      ..preimageError = null
      ..minimum = '0';
    final unpriced = await maxOf();
    trading.minimumError = StateError('offline');
    final unknown = await maxOf();

    expect(trading.preimages, hasLength(1));
    for (final max in [failed, unpriced, unknown]) {
      expect(max!.amount, d('0.98'));
    }
  });

  test('a claim that does not answer in time leaves KDF\'s Max', () {
    fakeAsync((async) {
      trading.preimageGate = Completer<void>();
      SwapMaxAmount? max;
      unawaited(maxOf().then((value) => max = value));

      async.elapse(
        AtomicSwapQuoteSource.claimFeeTimeout - const Duration(milliseconds: 1),
      );
      expect(max, isNull);

      async.elapse(const Duration(milliseconds: 1));
      expect(max!.amount, d('0.98'));
    });
  });

  group('when KDF\'s Max is slow', () {
    const kdfTakes = Duration(seconds: 15);

    test('the claim may take only what is left of the deadline', () {
      fakeAsync((async) {
        final start = DateTime(2026, 10, 5);
        trading
          ..maxGate = Completer<void>()
          ..preimageGate = Completer<void>();
        SwapMaxAmount? max;
        unawaited(
          maxOf(now: () => start.add(async.elapsed))
              .then((value) => max = value),
        );
        async.elapse(kdfTakes);
        trading.maxGate!.complete();

        final left = AtomicSwapQuoteSource.claimFeeDeadline - kdfTakes;
        async.elapse(left - const Duration(milliseconds: 1));
        expect(max, isNull);

        async.elapse(const Duration(milliseconds: 1));
        expect(max!.amount, d('0.98'));
      });
    });

    test('past the deadline, the claim is not read at all', () {
      fakeAsync((async) {
        final start = DateTime(2026, 10, 5);
        trading.maxGate = Completer<void>();
        SwapMaxAmount? max;
        unawaited(
          maxOf(now: () => start.add(async.elapsed))
              .then((value) => max = value),
        );
        async.elapse(AtomicSwapQuoteSource.claimFeeDeadline);
        trading.maxGate!.complete();
        async.flushMicrotasks();

        expect(max!.amount, d('0.98'));
        expect(trading.preimages, isEmpty);
      });
    });

    test('KDF\'s Max lands before Max stops waiting on the order book', () {
      fakeAsync((async) {
        trading
          ..maxGate = Completer<void>()
          ..preimageGate = Completer<void>();
        final max = askMax(async);
        async.elapse(kdfTakes);
        trading.maxGate!.complete();
        async.elapse(_budget - kdfTakes - _tick);

        expect(max.maxes![SwapLiquiditySource.atomic]!.amount, d('0.98'));
      });
    });

    test('an order-book-only pair whose Max answers at 30 s still lands', () {
      fakeAsync((async) {
        trading.maxGate = Completer<void>();
        final max = askMax(async, alone: true);
        async.elapse(const Duration(seconds: 30));
        expect(max.failure, isNull);
        trading.maxGate!.complete();
        async.flushMicrotasks();

        expect(max.maxes![SwapLiquiditySource.atomic]!.amount, d('0.98'));
      });
    });
  });

  test('a slow min_trading_vol read keeps KDF\'s Max', () {
    fakeAsync((async) {
      final start = DateTime(2026, 10, 5);
      trading.minimumGate = Completer<void>();
      SwapMaxAmount? max;
      unawaited(
        maxOf(now: () => start.add(async.elapsed)).then((value) => max = value),
      );

      async.elapse(AtomicSwapQuoteSource.claimFeeDeadline - _tick);
      expect(max, isNull);
      async.elapse(_tick);

      expect(max!.amount, d('0.98'));
      expect(max!.offerLimit, isFalse);
    });
  });

  group('when KDF\'s Max never comes', () {
    test('Max says the order book timed out', () {
      fakeAsync((async) {
        trading.maxGate = Completer<void>();
        final max = askMax(async);

        async.elapse(_budget - _tick);
        expect(max.failure, isNull);
        async.elapse(_tick);

        expect(
          max.failure,
          const SwapQuoteFailure(
            source: SwapLiquiditySource.atomic,
            kind: SwapQuoteFailureKind.timeout,
          ),
        );
      });
    });

    for (final preferred in [null, SwapLiquiditySource.atomic]) {
      final selected = preferred == null ? '' : ' with the order book selected';
      test('the routed Max is used$selected', () {
        fakeAsync((async) {
          trading.maxGate = Completer<void>();
          final max = askMax(
            async,
            routed: SwapMaxAmount(amount: d('0.99'), reservedForFees: d('0')),
            preferred: preferred,
          );

          async.elapse(_budget - _tick);
          expect(max.maxes, isNull);
          async.elapse(_tick);

          expect(max.maxes!.keys, [SwapLiquiditySource.routed]);
        });
      });
    }
  });

  test('takes the claim off before keeping to the decimals', () async {
    final avax = assetOf('AVAX', chainId: 43114, decimals: 9);
    final token = assetOf(
      'USDC-AVX20',
      parent: avax,
      chainId: 43114,
      decimals: 6,
    );
    trading
      ..maxTaker = '0.9876543219876'
      ..preimage = preimageOf(relCoinFee: coinFeeOf('AVAX', '0.0012345678912'));

    final max = await maxOf(from: avax, to: token);

    expect(trading.preimages.single.volume, '0.987654321');
    expect(max!.amount, d('0.986419753'));
    expect(max.reservedForFees, d('0.013580247'));
  });

  test('takes the claim off before stopping at the largest offer', () async {
    trading.bids = [
      bidOf('3000', '0.01', '0.977'),
      bidOf('2900', '0.979', '5'),
    ];

    final max = await maxOf();

    expect(max!.amount, d('0.977'));
    expect(max.offerLimit, isTrue);
    expect(max.reservedForFees, d('0.022'));
  });

  test('a claim larger than KDF\'s Max leaves nothing to sell', () async {
    trading.maxTaker = '0.001';

    final max = await maxOf();

    expect(max!.amount, d('0'));
    expect(max.reservedForFees, d('1'));
  });

  test('nothing to sell reads no claim', () async {
    trading.maxTaker = '0';

    expect((await maxOf())!.amount, d('0'));
    expect(trading.minimums, isNot(contains('USDC-ERC20')));
    expect(trading.preimages, isEmpty);
  });
}
