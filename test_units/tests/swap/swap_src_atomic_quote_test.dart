import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers how an order-book quote is priced: against one order that takes
/// the whole amount, with the engine's fees, and only for a pair the order
/// book may trade right now.
void main() {
  final now = DateTime(2026, 9, 24, 12, 30);
  final networks = SwapNetworks([eth, btc]);
  final usdtTrc20 = assetOf(
    'USDT-TRC20',
    subClass: CoinSubClass.trc20,
    chainId: 0,
    decimals: 6,
  );
  late SrcTrading trading;

  setUp(() => trading = SrcTrading());

  AtomicSwapQuoteSource source({
    bool Function(AssetId from, AssetId to)? tradingAllowed,
    bool Function()? clockValid,
    bool Function(AssetId asset)? isWalletOnly,
  }) => AtomicSwapQuoteSource(
    trading: trading,
    networks: () => networks,
    addressOf: (asset) async => '${asset.id}-address',
    tradingAllowed: tradingAllowed,
    clockValid: clockValid,
    isWalletOnly: isWalletOnly,
    now: () => now,
  );

  Future<SwapQuoteResult> ask(
    AtomicSwapQuoteSource source, {
    AssetId? from,
    AssetId? to,
    String amount = '1',
  }) async {
    final results = await source.quote(
      SwapQuoteRequest(from: from ?? btc, to: to ?? eth, amount: d(amount)),
    );
    return results.single;
  }

  SwapQuote available(SwapQuoteResult result) =>
      (result as SwapQuoteAvailable).quote;

  SwapQuoteFailure failure(SwapQuoteResult result) =>
      (result as SwapQuoteRejected).failure;

  group('one order, whole', () {
    test('sells the whole amount to the best order that can take it', () async {
      trading.bids = [
        bidOf('19', '0.1', '5'),
        bidOf('21', '0.1', '0.5'),
        bidOf('20', '0.1', '2'),
      ];

      final quote = available(await ask(source()));

      expect(quote.source, SwapLiquiditySource.atomic);
      expect(quote.routeKind, SwapRouteKind.direct);
      expect(quote.id, 'atomic');
      expect(quote.order, isNull);
      expect(quote.sellAmount, d('1'));
      expect(quote.expectedReceive, d('20'));
      expect(quote.guaranteedReceive, d('20'));
      expect(quote.fees, isEmpty);
      expect(quote.feesKnown, isTrue);
      expect(quote.quotedAt, now);
      expect(quote.fromAddress, 'BTC-address');
      expect(quote.toAddress, 'ETH-address');
      final plan = quote.payload! as AtomicSwapPlan;
      expect(plan.base, btc);
      expect(plan.rel, eth);
      expect(plan.volume, d('1'));
      expect(plan.price, d('20'));
      expect(trading.books.single, (base: 'BTC', rel: 'ETH'));
      expect(trading.preimages.single, (
        volume: '1',
        price: '20',
        method: SwapMethod.sell,
      ));
    });

    test('describes a peer-to-peer exchange, network by network', () async {
      final quote = available(await ask(source()));

      expect(quote.stages, [
        const SwapRouteStage(kind: SwapRouteStageKind.prepare),
        SwapRouteStage(
          kind: SwapRouteStageKind.send,
          network: networks.networkOf(btc),
          asset: btc,
        ),
        SwapRouteStage(
          kind: SwapRouteStageKind.exchange,
          network: 'Ethereum',
          asset: eth,
        ),
        SwapRouteStage(
          kind: SwapRouteStageKind.receive,
          network: 'Ethereum',
          asset: eth,
        ),
      ]);
    });
  });

  group('fees', () {
    test(
      'only fees paid out of the received coin lower the guarantee',
      () async {
        trading.preimage = preimageOf(
          takerFee: coinFeeOf('BTC', '0.0013'),
          feeToSendTakerFee: coinFeeOf('BTC', '0.00001'),
          baseCoinFee: coinFeeOf('BTC', '0.0002', fromVolume: true),
          relCoinFee: coinFeeOf('ETH', '0.001', fromVolume: true),
        );

        final quote = available(await ask(source()));

        expect(quote.guaranteedReceive, d('19.999'));
        expect(quote.expectedReceive, d('19.999'));
        expect(quote.fees, [
          SwapFeeComponent(
            kind: SwapFeeKind.dexFee,
            amount: d('0.0013'),
            deductedFromReceive: false,
            asset: btc,
            symbol: 'BTC',
          ),
          SwapFeeComponent(
            kind: SwapFeeKind.network,
            amount: d('0.00001'),
            deductedFromReceive: false,
            asset: btc,
            symbol: 'BTC',
          ),
          SwapFeeComponent(
            kind: SwapFeeKind.network,
            amount: d('0.0002'),
            deductedFromReceive: true,
            asset: btc,
            symbol: 'BTC',
          ),
          SwapFeeComponent(
            kind: SwapFeeKind.network,
            amount: d('0.001'),
            deductedFromReceive: true,
            asset: eth,
            symbol: 'ETH',
          ),
        ]);
      },
    );

    test('a token\'s fees in its network coin map to that coin', () async {
      trading
        ..bids = [bidOf('0.00005', '1', '1000')]
        ..preimage = preimageOf(
          takerFee: coinFeeOf('USDC-ERC20', '0.75'),
          feeToSendTakerFee: coinFeeOf('ETH', '0.0004'),
          baseCoinFee: coinFeeOf('ETH', '0.0006'),
          relCoinFee: coinFeeOf('BTC', '0.00002'),
        );

      final quote = available(await ask(source(), from: usdc, to: btc));

      expect(quote.fees.map((fee) => fee.asset), [usdc, eth, eth, btc]);
      expect(quote.guaranteedReceive, d('0.00005'));
    });

    test(
      'the bought token\'s network coin maps too; others stay symbols',
      () async {
        trading
          ..bids = [bidOf('60000', '0.001', '1')]
          ..preimage = preimageOf(
            baseCoinFee: coinFeeOf('KMD', '0.0001'),
            relCoinFee: coinFeeOf('ETH', '0.002'),
          );

        final quote = available(
          await ask(source(), from: btc, to: usdc, amount: '0.5'),
        );

        expect(quote.guaranteedReceive, d('30000'));
        expect(quote.fees.first.asset, isNull);
        expect(quote.fees.first.symbol, 'KMD');
        expect(quote.fees.first.tokenLabel, 'KMD');
        expect(quote.fees.last.asset, eth);
      },
    );

    test('a zero fee, or one KDF writes unreadably, is left out', () async {
      trading.preimage = preimageOf(
        takerFee: coinFeeOf('BTC', '0'),
        baseCoinFee: coinFeeOf('BTC', 'n/a'),
        relCoinFee: coinFeeOf('ETH', '0.001'),
      );

      final quote = available(await ask(source()));

      expect(quote.fees.single.amount, d('0.001'));
      expect(quote.feesKnown, isTrue);
      expect(quote.guaranteedReceive, d('20'));
    });

    test('a received-coin fee larger than the fill promises nothing', () async {
      trading.preimage = preimageOf(
        relCoinFee: coinFeeOf('ETH', '25', fromVolume: true),
      );

      final reason = failure(await ask(source()));

      expect(reason.kind, SwapQuoteFailureKind.belowMinimum);
      expect(reason.minimum, d('0.001'));
      expect(reason.source, SwapLiquiditySource.atomic);
    });
  });

  group('checks before the order book', () {
    test(
      'an asset the order book cannot trade makes the pair unsupported',
      () async {
        final custody = failure(await ask(source(), from: usdtTrc20));
        final walletOnly = failure(
          await ask(source(isWalletOnly: (asset) => asset == eth)),
        );

        expect(custody.kind, SwapQuoteFailureKind.pairUnsupported);
        expect(walletOnly.kind, SwapQuoteFailureKind.pairUnsupported);
        expect(trading.books, isEmpty);
      },
    );

    test('a trading restriction on the pair blocks it', () async {
      final asked = <(AssetId, AssetId)>[];
      final reason = failure(
        await ask(
          source(
            tradingAllowed: (from, to) {
              asked.add((from, to));
              return false;
            },
          ),
        ),
      );

      expect(reason.kind, SwapQuoteFailureKind.tradingBlocked);
      expect(asked, [(btc, eth)]);
      expect(trading.books, isEmpty);
    });

    test('a device clock that is off stops peer-to-peer pricing', () async {
      final reason = failure(
        await ask(
          source(tradingAllowed: (_, _) => true, clockValid: () => false),
        ),
      );

      expect(reason.kind, SwapQuoteFailureKind.clockInvalid);
      expect(trading.books, isEmpty);
    });

    test('a passing clock and restriction check lets pricing go on', () async {
      final result = await ask(
        source(tradingAllowed: (_, _) => true, clockValid: () => true),
      );

      expect(result, isA<SwapQuoteAvailable>());
    });

    test('an amount under the order book minimum names the minimum', () async {
      trading.minimum = '0.5';

      final reason = failure(await ask(source(), amount: '0.1'));

      expect(reason.kind, SwapQuoteFailureKind.belowMinimum);
      expect(reason.minimum, d('0.5'));
      expect(trading.books, isEmpty);
    });

    test('a minimum that cannot be read does not block pricing', () async {
      trading.minimum = 'n/a';
      final unreadable = await ask(source(), amount: '0.02');
      trading.minimumError = StateError('min_trading_vol failed');
      final failed = await ask(source(), amount: '0.02');

      expect(available(unreadable).sellAmount, d('0.02'));
      expect(available(failed).sellAmount, d('0.02'));
    });
  });
}
