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
    nativeMaxGasReserve: false,
    networks: () => SwapNetworks([eth, usdc]),
    timeout: timeout,
    catalogTimeout: catalogTimeout,
    now: () => clock,
  );

  group('KDF Max quotes', () {
    test(
      'Bitcoin miner fees and staked TRON use the original KDF Max',
      () async {
        final trx = assetOf('TRX', subClass: CoinSubClass.trx, decimals: 6);
        final routed = RoutedSwapQuoteSource(
          manager,
          networks: () => SwapNetworks([btc, trx, usdc]),
          nativeMaxGasReserve: true,
        );
        for (final (asset, fee) in [(btc, '0.0001'), (trx, '0')]) {
          manager.maximum = offerOf(
            from: asset,
            to: usdc,
            sell: '0.01',
            guaranteed: '5',
            networkFees: [
              RoutedSwapNetworkFee(
                ticker: asset.id,
                assetId: asset,
                amount: d(fee),
                requiredBalance: d(fee),
              ),
            ],
          );
          final result = (await routed.maxAmount(
            from: asset,
            to: usdc,
            balance: d('0.02'),
          ))!;
          expect(result.amount, d('0.01'));
          expect(result.quote!.guaranteedReceive, d('5'));
          expect(result.reservedForFees, d(fee));
        }
        expect(manager.maxCalls, 2);
        expect(manager.quotes, isEmpty);
      },
    );

    test(
      'uses the returned amount, required balance and exact minimum',
      () async {
        manager.maximum = offerOf(
          sell: '1.97',
          guaranteed: '5900',
          costs: [
            RoutedSwapCost(
              label: 'gas',
              amount: d('0.001'),
              kind: RoutedSwapCostKind.gas,
              isDeductedFromReceive: false,
              assetId: eth,
            ),
            RoutedSwapCost(
              label: 'included commission',
              amount: d('0.02'),
              kind: RoutedSwapCostKind.providerFee,
              isDeductedFromReceive: true,
              assetId: eth,
            ),
          ],
          networkFees: [
            RoutedSwapNetworkFee(
              ticker: 'ETH',
              assetId: eth,
              amount: d('0.001'),
              requiredBalance: d('0.03'),
            ),
          ],
        );
        final routed = source();
        final max = (await routed.maxAmount(
          from: eth,
          to: usdc,
          balance: d('2'),
        ))!;
        expect(max.amount, d('1.97'));
        expect(max.reservedForFees, d('0.03'));
        expect(max.quote!.guaranteedReceive, d('5900'));
        expect(max.quote!.costOnTopIn(eth), d('0.001'));
        expect(manager.maxCalls, 1);
        expect(manager.quotes, isEmpty);
        // Initial evaluation reuses this exact Max snapshot, not a second exact quote.
        final result = await routed.quote(
          SwapQuoteRequest(
            from: eth,
            to: usdc,
            amount: max.amount,
            maxSource: SwapLiquiditySource.routed,
          ),
        );
        expect((result.single as SwapQuoteAvailable).quote, max.quote);
        expect(manager.maxCalls, 1);
      },
    );

    test(
      'a refresh asks Max again and alternatives use its concrete amount',
      () async {
        manager.maximum = offerOf(sell: '1.9', order: RoutedSwapOrder.cheapest);
        final routed = source();
        await routed.maxAmount(from: eth, to: usdc, balance: d('2'));
        clock = clock.add(const Duration(seconds: 20));
        manager.maximum = offerOf(sell: '1.8', order: RoutedSwapOrder.cheapest);
        await routed.quote(
          SwapQuoteRequest(
            from: eth,
            to: usdc,
            amount: d('1.9'),
            maxSource: SwapLiquiditySource.routed,
            orders: {SwapQuoteOrder.cheapest, SwapQuoteOrder.fastest},
          ),
        );
        expect(manager.maxCalls, 2);
        expect(manager.quotes.single.amount, d('1.8'));
        expect(manager.quotes.single.order, RoutedSwapOrder.fastest);
      },
    );

    test('does not reuse an exact quote as Max', () async {
      final routed = source();
      await routed.quote(SwapQuoteRequest(from: eth, to: usdc, amount: d('1')));
      manager.maximum = offerOf(sell: '1.9');
      expect(
        (await routed.maxAmount(from: eth, to: usdc, balance: d('2')))!.amount,
        d('1.9'),
      );
      expect(manager.maxCalls, 1);
    });

    test('a token keeps KDF amount and separate gas funding', () async {
      manager.maximum = offerOf(
        from: usdc,
        to: eth,
        sell: '99',
        networkFees: [
          RoutedSwapNetworkFee(
            ticker: 'ETH',
            assetId: eth,
            amount: d('0.001'),
            requiredBalance: d('0.002'),
          ),
        ],
      );
      final max = (await source().maxAmount(
        from: usdc,
        to: eth,
        balance: d('100'),
      ))!;
      expect(max.amount, d('99'));
      expect(max.quote!.fundingOnTopIn(eth), d('0.002'));
    });

    test('a rejected Max retains named shortfall and locked funds', () async {
      manager.maxError = const RoutedSwapInsufficientBalanceException(
        coin: 'ETH',
        available: '0.01',
        required: '0.02',
        lockedBySwaps: '1',
        message: 'short',
      );
      await expectLater(
        source().maxAmount(from: usdc, to: eth, balance: d('100')),
        throwsA(
          isA<SwapMaxUnavailableException>()
              .having((e) => e.failure.available, 'available', d('0.01'))
              .having((e) => e.failure.minimum, 'required', d('0.02'))
              .having((e) => e.failure.lockedBySwaps, 'locked', d('1'))
              .having((e) => e.failure.asset, 'asset', eth),
        ),
      );
    });

    test('a rate limited Max pauses subsequent requests', () async {
      manager.maxError = const RoutedSwapRateLimitedException(
        message: 'rate limit',
      );
      final routed = source();
      for (var i = 0; i < 2; i++) {
        await expectLater(
          routed.maxAmount(from: eth, to: usdc, balance: d('2')),
          throwsA(
            isA<SwapMaxUnavailableException>().having(
              (e) => e.failure.kind,
              'kind',
              SwapQuoteFailureKind.rateLimited,
            ),
          ),
        );
      }
      expect(manager.maxCalls, 1);
    });

    test('timeout never falls back to full balance', () async {
      manager.hangMax = true;
      await expectLater(
        source(timeout: Duration.zero)
            .maxAmount(from: eth, to: usdc, balance: d('2')),
        throwsA(
          isA<SwapMaxUnavailableException>().having(
            (e) => e.failure.kind,
            'kind',
            SwapQuoteFailureKind.timeout,
          ),
        ),
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

      final assets = await source(catalogTimeout: Duration.zero)
          .assets(known: {eth, usdc, paxg, btc}, activated: {eth, usdc, btc});

      expect(assets.source, SwapLiquiditySource.routed);
      expect(assets.quotable, {eth, usdc, btc});
      expect(assets.onceActive, {paxg});
      final update = await assets.update!;
      expect(update.status, SwapCatalogStatus.unavailable);
      expect(update.quotable, {eth, usdc, btc});
      expect(update.onceActive, {paxg});
    },
  );

  test(
    'KDF confirms active Bitcoin and TRON eligibility before quoting',
    () async {
      final trx = assetOf('TRX', subClass: CoinSubClass.trx, decimals: 6);
      final usdt = assetOf(
        'USDT-TRC20',
        subClass: CoinSubClass.trc20,
        parent: trx,
      );
      manager.eligible = {eth, usdt};
      final assets = await source().assets(
        known: {eth, btc, trx, usdt},
        activated: {eth, btc, usdt},
      );
      expect(assets.quotable, {eth, btc, usdt});
      expect(assets.onceActive, {trx});
      final confirmed = await assets.update!;
      expect(confirmed.quotable, {eth, usdt});
      expect(confirmed.onceActive, {trx});
    },
  );
}
