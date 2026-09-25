// The analyzer does not treat test_units as tests, so @visibleForTesting
// members read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the order book's answers when pricing cannot finish, prices to
/// look at, and what the order book says about amounts and assets.
void main() {
  final usdtTrc20 = assetOf(
    'USDT-TRC20',
    subClass: CoinSubClass.trc20,
    chainId: 0,
    decimals: 6,
  );
  late SrcTrading trading;

  setUp(() => trading = SrcTrading());

  AtomicSwapQuoteSource source({
    Future<String?> Function(AssetId asset)? addressOf,
    bool Function(AssetId asset)? isWalletOnly,
  }) => AtomicSwapQuoteSource(
    trading: trading,
    networks: () => SwapNetworks([eth, btc]),
    addressOf: addressOf,
    isWalletOnly: isWalletOnly,
  );

  Future<SwapQuoteResult> ask({
    AssetId? from,
    bool indicative = false,
    Future<String?> Function(AssetId asset)? addressOf,
  }) async => (await source(addressOf: addressOf).quote(
    SwapQuoteRequest(
      from: from ?? btc,
      to: eth,
      amount: d('1'),
      indicative: indicative,
    ),
  )).single;

  SwapQuote available(SwapQuoteResult result) =>
      (result as SwapQuoteAvailable).quote;

  SwapQuoteFailure failure(SwapQuoteResult result) =>
      (result as SwapQuoteRejected).failure;

  const shortOfBtc = TradePreimageRpcErrorNotSufficientBalanceException(
    coin: 'BTC',
    available: BigDecimal('0.2'),
    required: BigDecimal('1.0001'),
  );
  const shortOfGas = TradePreimageRpcErrorNotSufficientBaseCoinBalanceException(
    coin: 'ETH',
    available: BigDecimal('0'),
    required: BigDecimal('0.002'),
  );
  const tooSmall = TradePreimageRpcErrorVolumeTooLowException(
    coin: 'BTC',
    volume: BigDecimal('0.0001'),
    threshold: BigDecimal('0.0007'),
  );

  group('when pricing cannot finish', () {
    test('an order book that cannot be read is a service error', () async {
      trading.bookError = StateError('orderbook offline');

      final reason = failure(await ask());

      expect(reason.kind, SwapQuoteFailureKind.serviceError);
      expect(reason.detail, contains('orderbook offline'));
      expect(reason.source, SwapLiquiditySource.atomic);
    });

    test('no single order able to take the whole amount is no route', () async {
      trading.bids = [bidOf('20', '0.01', '0.5'), bidOf('19', '2', '5')];

      final reason = failure(await ask());

      expect(reason.kind, SwapQuoteFailureKind.noRoute);
      expect(trading.preimages, isEmpty);
    });

    test('a wallet short of the amount is insufficient funds', () async {
      trading.preimageError = shortOfBtc;

      final reason = failure(await ask());

      expect(reason.kind, SwapQuoteFailureKind.insufficientFunds);
      expect(reason.detail, 'BTC');
      expect(reason.source, SwapLiquiditySource.atomic);
    });

    test('a wallet short of network coin is insufficient funds too', () async {
      trading.preimageError = shortOfGas;

      final reason = failure(await ask(from: usdc));

      expect(reason.kind, SwapQuoteFailureKind.insufficientFunds);
      expect(reason.detail, 'ETH');
    });

    test('a shortfall carries the amount required', () async {
      trading.preimageError = shortOfGas;

      expect(failure(await ask(from: usdc)).minimum, d('0.002'));
    });

    test('a shortfall names the coin that is short', () async {
      trading.preimageError = shortOfGas;

      expect(failure(await ask(from: usdc)).asset, eth);
    });

    test(
      'an amount under the engine\'s fee threshold is below minimum',
      () async {
        trading.preimageError = tooSmall;

        final reason = failure(await ask());

        expect(reason.kind, SwapQuoteFailureKind.belowMinimum);
        expect(reason.source, SwapLiquiditySource.atomic);
      },
    );

    test('a volume too low names the threshold', () async {
      trading.preimageError = tooSmall;

      expect(failure(await ask()).minimum, d('0.0007'));
    });

    test('any other preimage failure keeps the price, without costs', () async {
      trading.preimageError = const TradePreimageRpcErrorNoSuchCoinException(
        coin: 'BTC',
      );
      final typed = available(await ask());
      trading.preimageError = StateError('preimage timed out');
      final untyped = available(await ask());

      for (final quote in [typed, untyped]) {
        expect(quote.guaranteedReceive, d('20'));
        expect(quote.fees, isEmpty);
        expect(quote.feesKnown, isFalse);
      }
      final priced = SwapPricingService(
        FakePriceSource({btc: d('60000'), eth: d('3000')}),
      ).price(typed);
      expect(priced.pricing.isComplete, isFalse);
      expect(priced.isRankable, isFalse);
    });
  });

  group('prices to look at', () {
    test('a price above the balance skips the engine\'s fee check', () async {
      trading.preimageError = shortOfBtc;

      final quote = available(await ask(indicative: true));

      expect(quote.guaranteedReceive, d('20'));
      expect(quote.feesKnown, isFalse);
      expect(trading.preimages, isEmpty);
    });

    test(
      're-pricing a quote asks for the same pair, amount and fees',
      () async {
        final result = await source().requote(
          quoteOf(
            source: SwapLiquiditySource.atomic,
            from: btc,
            to: eth,
            sell: '2',
          ),
        );

        final quote = available(result);
        expect(quote.sellAmount, d('2'));
        expect(quote.guaranteedReceive, d('40'));
        expect(quote.feesKnown, isTrue);
        expect(trading.preimages.single.volume, '2');
      },
    );
  });

  group('addresses', () {
    test('an address that cannot be read is left blank', () async {
      final quote = available(
        await ask(
          addressOf: (asset) async =>
              asset == eth ? throw StateError('locked') : 'bc1-address',
        ),
      );

      expect(quote.fromAddress, 'bc1-address');
      expect(quote.toAddress, isNull);
    });

    test('without an address reader the quote carries none', () async {
      final quote = available(await ask());

      expect(quote.fromAddress, isNull);
      expect(quote.toAddress, isNull);
    });
  });

  group('amounts', () {
    test('the minimum is KDF\'s minimum trading volume', () async {
      expect(await source().minimumAmount(from: btc), d('0.001'));

      trading.minimum = 'n/a';
      expect(await source().minimumAmount(from: btc), isNull);

      trading.minimumError = StateError('offline');
      expect(await source().minimumAmount(from: btc), isNull);
    });

    test('Max is KDF\'s max taker volume, keeping the rest for fees', () async {
      trading.maxTaker = '0.9';

      final max = await source().maxAmount(from: btc, to: eth, balance: d('1'));

      expect(
        max,
        SwapMaxAmount(
          amount: d('0.9'),
          reservedForFees: d('0.1'),
          feeAsset: btc,
        ),
      );
      expect(trading.maxCalls.single, (coin: 'BTC', tradeWith: 'ETH'));
    });

    test('Max never exceeds the balance', () async {
      trading.maxTaker = '5';

      final max = await source().maxAmount(from: btc, to: eth, balance: d('2'));

      expect(max!.amount, d('2'));
      expect(max.reservedForFees, d('0'));
    });

    test('a negative max reads as nothing sellable', () async {
      trading.maxTaker = '-1';

      final max = await source().maxAmount(from: btc, to: eth, balance: d('2'));

      expect(max!.amount, d('0'));
    });

    test('a negative max holds back the whole balance, no more', () async {
      trading.maxTaker = '-1';

      final max = await source().maxAmount(from: btc, to: eth, balance: d('2'));

      expect(max!.reservedForFees, d('2'));
    });

    test('a max that cannot be read or fetched is unknown', () async {
      trading.maxTaker = 'n/a';
      expect(
        await source().maxAmount(from: btc, to: eth, balance: d('1')),
        isNull,
      );

      trading.maxTakerError = StateError('offline');
      expect(
        await source().maxAmount(from: btc, to: eth, balance: d('1')),
        isNull,
      );
    });
  });

  group('assets', () {
    test(
      'lists active tradable assets now, inactive ones once active',
      () async {
        final assets = await source(
          isWalletOnly: (asset) => asset == gleec,
        ).assets(known: {eth, btc, gleec, usdtTrc20}, activated: {eth, gleec});

        expect(assets.source, SwapLiquiditySource.atomic);
        expect(assets.status, SwapCatalogStatus.fresh);
        expect(assets.quotable, {eth});
        expect(assets.onceActive, {btc});
      },
    );

    test('custody-backed and config wallet-only assets never trade', () {
      final walletOnly = source(isWalletOnly: (asset) => asset == gleec);

      expect(walletOnly.source, SwapLiquiditySource.atomic);
      expect(walletOnly.canTrade(eth), isTrue);
      expect(walletOnly.canTrade(gleec), isFalse);
      expect(source().canTrade(usdtTrc20), isFalse);
      expect(AtomicSwapQuoteSource.canTradeWith(gleec, null), isTrue);
      expect(AtomicSwapQuoteSource.canTradeWith(usdtTrc20, null), isFalse);
    });
  });

  test('orders missing a price or size, or priced at zero, are skipped', () {
    final best = AtomicSwapQuoteSource.bestFillingBid([
      bidOf(null, '0', '5'),
      bidOf('30', '0', null),
      bidOf('abc', '0', '5'),
      bidOf('0', '0', '5'),
      bidOf('10', null, '5'),
    ], d('1'));

    expect(best, (price: d('10'), maxVolume: d('5')));
  });
}
