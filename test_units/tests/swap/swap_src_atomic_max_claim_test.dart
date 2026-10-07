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
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers Max on the order book when the coin sold also pays the gas to claim
/// what arrives, as for a token on its own network.
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
          maxOf(
            now: () => start.add(async.elapsed),
          ).then((value) => max = value),
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
          maxOf(
            now: () => start.add(async.elapsed),
          ).then((value) => max = value),
        );
        async.elapse(AtomicSwapQuoteSource.claimFeeDeadline);
        trading.maxGate!.complete();
        async.flushMicrotasks();

        expect(max!.amount, d('0.98'));
        expect(trading.preimages, isEmpty);
      });
    });
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
