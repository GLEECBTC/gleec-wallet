import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

RoutedSwapCost _gasCost(String amount) => RoutedSwapCost(
  label: 'Network fee',
  amount: d(amount),
  kind: RoutedSwapCostKind.gas,
  isDeductedFromReceive: false,
  assetId: eth,
);

/// A LI.FI provider fee: [onTop] for `included: false`. Without [asset], the
/// provider's own symbol names it.
RoutedSwapCost _providerFee(
  String amount,
  AssetId? asset, {
  bool onTop = true,
}) => RoutedSwapCost(
  label: 'Gas receiver fee',
  amount: d(amount),
  kind: RoutedSwapCostKind.providerFee,
  isDeductedFromReceive: !onTop,
  assetId: asset,
  symbol: asset == null ? 'ETH' : null,
);

/// Covers what the aggregator allows to be sold: Max from the costs of a
/// route priced moments ago, or from KDF's own probe, and what the picker
/// shows when the aggregator's list cannot be read in time.
void main() {
  late SrcRoutedSwaps manager;
  late DateTime clock;

  setUp(() {
    manager = SrcRoutedSwaps();
    clock = DateTime(2026, 9, 24, 12);
  });

  RoutedSwapQuoteSource source({
    Duration timeout = const Duration(seconds: 20),
    Duration catalogTimeout = const Duration(seconds: 10),
  }) => RoutedSwapQuoteSource(
    manager,
    networks: () => SwapNetworks([eth, usdc]),
    timeout: timeout,
    catalogTimeout: catalogTimeout,
    now: () => clock,
  );

  /// Prices [from] for [to] once, with [gas] of network fee in [from], and
  /// [costs] itemised.
  Future<RoutedSwapQuoteSource> priced(
    AssetId from, {
    AssetId? to,
    String gas = '0.0005',
    String amount = '1',
    List<RoutedSwapCost> costs = const [],
    RoutedSwapQuoteSource? into,
  }) async {
    final routed = into ?? source();
    manager.respond = (call) => offerOf(
      from: call.from,
      to: call.to,
      sell: '${call.amount}',
      costs: costs,
      networkFees: [
        RoutedSwapNetworkFee(ticker: from.id, assetId: from, amount: d(gas)),
        RoutedSwapNetworkFee(ticker: 'USDC-ERC20', amount: d('5')),
      ],
    );
    await routed.quote(
      SwapQuoteRequest(from: from, to: to ?? usdc, amount: d(amount)),
    );
    return routed;
  }

  group('Max on a native coin', () {
    test(
      'reuses a fresh quote\'s gas, times three, instead of probing',
      () async {
        final routed = source();
        manager.respond = (call) => offerOf(
          networkFees: [
            RoutedSwapNetworkFee(
              ticker: 'ETH',
              assetId: eth,
              amount: d('0.0005'),
            ),
            RoutedSwapNetworkFee(ticker: 'ETH', amount: d('0.0001')),
            RoutedSwapNetworkFee(ticker: 'USDC-ERC20', amount: d('5')),
          ],
        );
        await routed.quote(
          SwapQuoteRequest(from: eth, to: usdc, amount: d('1')),
        );

        final max = await routed.maxAmount(
          from: eth,
          to: usdc,
          balance: d('2'),
        );

        expect(
          max,
          SwapMaxAmount(
            amount: d('1.9982'),
            reservedForFees: d('0.0018'),
            feeAsset: eth,
          ),
        );
        expect(manager.maxCalls, 0);
      },
    );

    test('also keeps back a provider fee charged on top in the coin', () async {
      final routed = await priced(
        eth,
        costs: [_gasCost('0.0005'), _providerFee('0.0012', eth)],
      );

      final max = await routed.maxAmount(from: eth, to: usdc, balance: d('2'));

      expect(
        max,
        SwapMaxAmount(
          amount: d('1.9973'),
          reservedForFees: d('0.0027'),
          feeAsset: eth,
          reserveCovers: SwapMaxReserve.networkAndProviderFees,
        ),
      );
    });

    test(
      'keeps back no fee taken from what arrives or paid elsewhere',
      () async {
        final routed = await priced(
          eth,
          costs: [
            _providerFee('0.0012', eth, onTop: false),
            _providerFee('5', usdc),
            // A token the wallet does not know, named only by the provider.
            _providerFee('0.0012', null),
          ],
        );

        final max = await routed.maxAmount(
          from: eth,
          to: usdc,
          balance: d('2'),
        );

        expect(
          max,
          SwapMaxAmount(
            amount: d('1.9985'),
            reservedForFees: d('0.0015'),
            feeAsset: eth,
          ),
        );
      },
    );

    test('rounds the reserve up and the amount down to the coin', () async {
      final coarse = assetOf('CRS', decimals: 2);

      final routed = await priced(coarse, gas: '0.0006');
      final max = await routed.maxAmount(
        from: coarse,
        to: usdc,
        balance: d('2'),
      );

      expect(max!.reservedForFees, d('0.01'));
      expect(max.amount, d('1.99'));
    });

    test('a coin without known decimals keeps the exact reserve', () async {
      final exact = assetOf('EXA', decimals: null);

      final routed = await priced(exact, gas: '0.0006');
      final max = await routed.maxAmount(
        from: exact,
        to: usdc,
        balance: d('2'),
      );

      expect(max!.reservedForFees, d('0.0018'));
      expect(max.amount, d('1.9982'));
    });

    test('a balance smaller than the reserve can sell nothing', () async {
      final routed = await priced(eth);

      final max = await routed.maxAmount(
        from: eth,
        to: usdc,
        balance: d('0.001'),
      );

      expect(max!.amount, d('0'));
      expect(max.reservedForFees, d('0.0015'));
    });

    test('the newest fresh quote of the pair decides', () async {
      final routed = await priced(eth);
      clock = clock.add(const Duration(seconds: 10));
      await priced(eth, gas: '0.0007', amount: '2', into: routed);

      final max = await routed.maxAmount(from: eth, to: usdc, balance: d('2'));

      expect(max!.reservedForFees, d('0.0021'));
      expect(manager.maxCalls, 0);
    });

    test('a quote for another pair is not used', () async {
      final routed = await priced(eth);

      await routed.maxAmount(from: eth, to: btc, balance: d('2'));

      expect(manager.maxCalls, 1);
    });

    test('a quote older than a minute is not trusted', () async {
      final routed = await priced(eth);
      clock = clock.add(const Duration(seconds: 61));
      manager.max = RoutedSwapMaxSell(
        amount: d('1.99'),
        reservedForFees: d('0.01'),
        feeAsset: eth,
      );

      final max = await routed.maxAmount(from: eth, to: usdc, balance: d('2'));

      expect(manager.maxCalls, 1);
      expect(
        max,
        SwapMaxAmount(
          amount: d('1.99'),
          reservedForFees: d('0.01'),
          feeAsset: eth,
        ),
      );
    });
  });

  group('Max on a token', () {
    /// Prices USDC for ETH once: gas in ETH, and on top a fee in ETH and,
    /// unless [tokenFee] is null, one in USDC.
    Future<RoutedSwapQuoteSource> pricedToken({String? tokenFee}) async {
      final routed = source();
      manager.respond = (call) => offerOf(
        from: call.from,
        to: call.to,
        sell: '${call.amount}',
        costs: [
          _gasCost('0.0005'),
          _providerFee('0.0012', eth),
          if (tokenFee != null) _providerFee(tokenFee, usdc),
        ],
        networkFees: [
          RoutedSwapNetworkFee(
            ticker: eth.id,
            assetId: eth,
            amount: d('0.0005'),
          ),
        ],
      );
      await routed.quote(SwapQuoteRequest(from: usdc, to: eth, amount: d('1')));
      return routed;
    }

    test('keeps back only a fee charged on top in the token', () async {
      final routed = await pricedToken(tokenFee: '1.2');

      final max = await routed.maxAmount(
        from: usdc,
        to: eth,
        balance: d('500'),
      );

      expect(manager.maxCalls, 0, reason: 'the quote moments ago stood in');
      expect(
        max,
        SwapMaxAmount(
          amount: d('498.8'),
          reservedForFees: d('1.2'),
          feeAsset: usdc,
          reserveCovers: SwapMaxReserve.providerFees,
        ),
      );
    });

    test('sells the whole balance with no fee on top in the token', () async {
      final routed = await pricedToken();

      final max = await routed.maxAmount(
        from: usdc,
        to: eth,
        balance: d('500'),
      );

      expect(manager.maxCalls, 0);
      expect(
        max,
        SwapMaxAmount(amount: d('500'), reservedForFees: d('0'), feeAsset: eth),
      );
    });
  });

  group('Max from KDF', () {
    test('a token without a fresh price asks KDF', () async {
      manager.max = RoutedSwapMaxSell(
        amount: d('500'),
        reservedForFees: d('0'),
        feeAsset: eth,
      );

      final max = await source().maxAmount(
        from: usdc,
        to: eth,
        balance: d('500'),
      );

      expect(manager.maxCalls, 1);
      expect(
        max,
        SwapMaxAmount(amount: d('500'), reservedForFees: d('0'), feeAsset: eth),
      );
    });

    test('a reserve KDF keeps for gas alone is network fees', () async {
      manager.max = RoutedSwapMaxSell(
        amount: d('1.9985'),
        reservedForFees: d('0.0015'),
        feeAsset: eth,
      );

      final max = await source().maxAmount(
        from: eth,
        to: usdc,
        balance: d('2'),
      );

      expect(max!.reserveCovers, SwapMaxReserve.networkFees);
    });

    test('a provider fee KDF keeps back is named with the gas', () async {
      manager.max = RoutedSwapMaxSell(
        amount: d('1.9973'),
        reservedForFees: d('0.0027'),
        feeAsset: eth,
        reservedForProviderFees: d('0.0012'),
      );

      final max = await source().maxAmount(
        from: eth,
        to: usdc,
        balance: d('2'),
      );

      expect(max!.reserveCovers, SwapMaxReserve.networkAndProviderFees);
    });

    test('a token\'s reserve from KDF is provider fees alone', () async {
      // Rounded up to the token's places, the reserve exceeds the fee.
      manager.max = RoutedSwapMaxSell(
        amount: d('498.799999'),
        reservedForFees: d('1.200001'),
        feeAsset: usdc,
        reservedForProviderFees: d('1.2000005'),
      );

      final max = await source().maxAmount(
        from: usdc,
        to: eth,
        balance: d('500'),
      );

      expect(max!.reserveCovers, SwapMaxReserve.providerFees);
      expect(max.feeAsset, usdc);
    });

    test('a Max KDF cannot work out is unknown', () async {
      manager.maxError = StateError('probe failed');

      expect(
        await source().maxAmount(from: eth, to: usdc, balance: d('2')),
        isNull,
      );
    });

    test('a Max KDF takes too long to work out is unknown', () async {
      manager.hangMax = true;

      final max = await source(
        timeout: Duration.zero,
      ).maxAmount(from: eth, to: usdc, balance: d('2'));

      expect(max, isNull);
    });
  });

  group('Max under a rate limit', () {
    const limited = RoutedSwapRateLimitedException(message: 'slow down');

    test('probes nothing while quotes are refused', () async {
      final routed = source();
      manager.quoteError = limited;
      await routed.quote(SwapQuoteRequest(from: eth, to: usdc, amount: d('1')));

      final max = await routed.maxAmount(from: eth, to: usdc, balance: d('2'));

      expect(max, isNull);
      expect(manager.maxCalls, 0);
    });

    test('probes nothing for a token either, whose Max is a quote', () async {
      final routed = source();
      manager.quoteError = limited;
      await routed.quote(SwapQuoteRequest(from: usdc, to: eth, amount: d('1')));

      final max = await routed.maxAmount(
        from: usdc,
        to: eth,
        balance: d('500'),
      );

      expect(max, isNull);
      expect(manager.maxCalls, 0);
    });

    test('a probe refused for the limit pauses quoting', () async {
      final routed = source();
      manager.maxError = limited;

      final max = await routed.maxAmount(from: eth, to: usdc, balance: d('2'));
      final results = await routed.quote(
        SwapQuoteRequest(from: eth, to: usdc, amount: d('1')),
      );

      expect(max, isNull);
      expect(manager.quotes, isEmpty);
      expect(
        (results.single as SwapQuoteRejected).failure.kind,
        SwapQuoteFailureKind.rateLimited,
      );
    });
  });

  test('the aggregator has no fixed minimum', () async {
    expect(await source().minimumAmount(from: eth), isNull);
  });

  test(
    'a catalog read that takes too long keeps the wallet\'s guess',
    () async {
      manager.hangEligible = true;
      final paxg = assetOf('PAXG-ERC20', parent: eth);

      final assets = await source(
        catalogTimeout: Duration.zero,
      ).assets(known: {eth, usdc, paxg, btc}, activated: {eth, usdc, btc});

      expect(assets.source, SwapLiquiditySource.routed);
      expect(assets.quotable, {eth, usdc});
      expect(assets.onceActive, {paxg});
      final update = await assets.update!;
      expect(update.status, SwapCatalogStatus.unavailable);
      expect(update.quotable, {eth, usdc});
      expect(update.onceActive, {paxg});
    },
  );
}
