import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers what the aggregator allows to be sold: Max from the gas of a
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

  /// Prices [from] for [to] once, with [gas] of network fee in [from].
  Future<RoutedSwapQuoteSource> priced(
    AssetId from, {
    AssetId? to,
    String gas = '0.0005',
    String amount = '1',
    RoutedSwapQuoteSource? into,
  }) async {
    final routed = into ?? source();
    manager.respond = (call) => offerOf(
      from: call.from,
      to: call.to,
      sell: '${call.amount}',
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

  group('Max from KDF', () {
    test('a token always asks KDF, which keeps nothing back', () async {
      final routed = await priced(usdc, to: eth);
      manager.max = RoutedSwapMaxSell(
        amount: d('500'),
        reservedForFees: d('0'),
        feeAsset: eth,
      );

      final max = await routed.maxAmount(
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
      expect(assets.status, SwapCatalogStatus.unavailable);
      expect(assets.quotable, {eth, usdc});
      expect(assets.onceActive, {paxg});
    },
  );
}
