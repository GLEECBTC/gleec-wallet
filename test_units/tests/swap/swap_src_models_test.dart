import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_test_fixtures.dart';

/// Covers the swap value types every screen reads: costs, prices, a quote's
/// expiry, rates and net return, requests, pair support and network names.
void main() {
  group('costs', () {
    SwapFeeComponent fee({AssetId? asset, String? symbol}) => SwapFeeComponent(
      kind: SwapFeeKind.network,
      amount: d('0.001'),
      deductedFromReceive: false,
      asset: asset,
      symbol: symbol,
    );

    test('a cost is labelled by its asset, else the provider\'s symbol', () {
      expect(fee(asset: usdc).tokenLabel, usdc.symbol.configSymbol);
      expect(
        fee(asset: usdc, symbol: 'X').tokenLabel,
        usdc.symbol.configSymbol,
      );
      expect(fee(symbol: 'WETH').tokenLabel, 'WETH');
      expect(fee().tokenLabel, '');
    });

    test('pricing a cost changes only its dollar value', () {
      final priced = fee(asset: eth, symbol: 'ETH').withUsd(d('3'));

      expect(priced.usdValue, d('3'));
      expect(priced.withUsd(null), fee(asset: eth, symbol: 'ETH'));
    });

    test('an approval compares by asset, amount and reset', () {
      final approval = SwapApprovalRequirement(
        asset: usdc,
        exactAmount: d('100'),
        resetsFirst: true,
      );

      expect(
        approval,
        SwapApprovalRequirement(
          asset: usdc,
          exactAmount: d('100'),
          resetsFirst: true,
        ),
      );
      expect(
        approval,
        isNot(
          SwapApprovalRequirement(
            asset: usdc,
            exactAmount: d('100'),
            resetsFirst: false,
          ),
        ),
      );
    });
  });

  group('dollar figures', () {
    test('a total needs both the network and the swap costs', () {
      expect(
        SwapQuotePricing(
          networkCostUsd: d('3'),
          swapCostUsd: d('2'),
        ).totalCostUsd,
        d('5'),
      );
      expect(SwapQuotePricing(networkCostUsd: d('3')).totalCostUsd, isNull);
      expect(SwapQuotePricing(swapCostUsd: d('2')).totalCostUsd, isNull);
    });

    test('price impact is the share of value lost against the market', () {
      expect(
        SwapQuotePricing(payUsd: d('3000'), expectedUsd: d('2970')).priceImpact,
        d('0.01'),
      );
      expect(
        SwapQuotePricing(payUsd: d('0'), expectedUsd: d('1')).priceImpact,
        isNull,
      );
      expect(SwapQuotePricing(payUsd: d('3000')).priceImpact, isNull);
    });
  });

  group('a quote', () {
    test('may be relied on for one minute after pricing', () {
      final quotedAt = DateTime(2026, 9, 24, 12);
      final quote = quoteOf(quotedAt: quotedAt);

      expect(quote.expiresAt, quotedAt.add(const Duration(minutes: 1)));
      expect(
        quote.isExpiredAt(quotedAt.add(const Duration(seconds: 59))),
        isFalse,
      );
      expect(quote.isExpiredAt(quote.expiresAt), isTrue);
    });

    test('rates are per unit sold, at the expected and at the minimum', () {
      final quote = quoteOf(sell: '2', expected: '6000', guaranteed: '5970');
      final nothing = quoteOf(sell: '0');

      expect(quote.expectedRate, d('3000'));
      expect(quote.guaranteedRate, d('2985'));
      expect(nothing.expectedRate, isNull);
      expect(nothing.guaranteedRate, isNull);
    });

    test('needs approval only when a permission must be granted', () {
      expect(quoteOf().requiresApproval, isFalse);
      expect(
        quoteOf(
          approval: SwapApprovalRequirement(
            asset: eth,
            exactAmount: d('1'),
            resetsFirst: false,
          ),
        ).requiresApproval,
        isTrue,
      );
    });

    test('nets out costs the receive does not already include', () {
      SwapFeeComponent cost(String? usd, {bool deducted = false}) =>
          SwapFeeComponent(
            kind: SwapFeeKind.swap,
            amount: d('1'),
            deductedFromReceive: deducted,
            asset: usdc,
            usdValue: usd == null ? null : d(usd),
          );

      expect(quoteOf().netReturnUsd, d('2982'));
      expect(
        quoteOf(fees: [cost('5'), cost(null, deducted: true)]).netReturnUsd,
        d('2980'),
      );

      final hidden = quoteOf(fees: [cost('5'), cost(null)]);
      expect(hidden.netReturnUsd, isNull);
      expect(hidden.isRankable, isFalse);

      final incomplete = quoteOf(pricing: SwapQuotePricing(minimumUsd: d('1')));
      expect(incomplete.netReturnUsd, isNull);
      expect(incomplete.isRankable, isFalse);
    });

    test('lists the costs of one kind', () {
      final quote = quoteOf(
        fees: [
          SwapFeeComponent(
            kind: SwapFeeKind.dexFee,
            amount: d('0.1'),
            deductedFromReceive: false,
          ),
          SwapFeeComponent(
            kind: SwapFeeKind.network,
            amount: d('0.2'),
            deductedFromReceive: false,
          ),
        ],
      );

      expect(quote.feesOf(SwapFeeKind.dexFee).single.amount, d('0.1'));
      expect(quote.feesOf(SwapFeeKind.swap), isEmpty);
    });

    test('re-pricing keeps the costs unless new ones are given', () {
      final quote = quoteOf(payload: 'plan');
      final pricing = SwapQuotePricing(payUsd: d('1'), isComplete: true);

      final repriced = quote.withPricing(pricing);
      final refeed = quote.withPricing(pricing, fees: const []);

      expect(repriced.pricing, pricing);
      expect(repriced.fees, same(quote.fees));
      expect(repriced.payload, 'plan');
      expect(repriced, quote.withPricing(pricing));
      expect(refeed.fees, isEmpty);
    });
  });

  group('requests', () {
    final request = SwapQuoteRequest(
      from: eth,
      to: usdc,
      amount: d('1'),
      slippage: 0.01,
      indicative: true,
    );

    test('asking for other routes keeps the rest of the request', () {
      final fastest = request.withOrders({SwapQuoteOrder.fastest});

      expect(
        fastest,
        SwapQuoteRequest(
          from: eth,
          to: usdc,
          amount: d('1'),
          orders: {SwapQuoteOrder.fastest},
          slippage: 0.01,
          indicative: true,
        ),
      );
      expect(fastest, isNot(request));
    });

    test('a price to look at is not the same request as one to start', () {
      expect(
        request,
        isNot(
          SwapQuoteRequest(from: eth, to: usdc, amount: d('1'), slippage: 0.01),
        ),
      );
    });

    test('a max compares by amount, reserve and fee coin', () {
      final max = SwapMaxAmount(
        amount: d('1'),
        reservedForFees: d('0.1'),
        feeAsset: eth,
      );

      expect(
        max,
        SwapMaxAmount(amount: d('1'), reservedForFees: d('0.1'), feeAsset: eth),
      );
      expect(
        max,
        isNot(SwapMaxAmount(amount: d('1'), reservedForFees: d('0.1'))),
      );
    });
  });

  group('pair support', () {
    test('compares by sources, gap and the assets it names', () {
      final orderBookOnly = SwapPairSupport(
        sources: const {SwapLiquiditySource.atomic},
        routesUnavailableFor: gleec,
      );

      expect(
        orderBookOnly,
        SwapPairSupport(
          sources: const {SwapLiquiditySource.atomic},
          routesUnavailableFor: gleec,
        ),
      );
      expect(orderBookOnly.isSupported, isTrue);
      expect(
        SwapPairSupport(gap: SwapPairGap.notTradable, limitingAsset: btc),
        isNot(
          SwapPairSupport(gap: SwapPairGap.sourcesDisjoint, limitingAsset: btc),
        ),
      );
      expect(const SwapPairSupport().isSupported, isFalse);
    });

    test('an empty catalog knows no source and no asset', () {
      expect(SwapCatalog.empty.of(SwapLiquiditySource.routed), isNull);
      expect(SwapCatalog.empty.assets, isEmpty);
      expect(SwapCatalog.empty.isIncomplete, isFalse);
    });
  });

  group('networks', () {
    final atom = assetOf(
      'ATOM',
      subClass: CoinSubClass.tendermint,
      chainId: 0,
      decimals: 6,
    );
    final iris = assetOf(
      'IRIS-IBC_ATOM',
      subClass: CoinSubClass.tendermintToken,
      parent: atom,
      chainId: 0,
      decimals: 6,
    );
    final usdcArb = assetOf(
      'USDC-ARB20',
      subClass: CoinSubClass.arbitrum,
      parent: assetOf('ETH-ARB20', subClass: CoinSubClass.arbitrum),
      chainId: 42161,
    );

    test('a token lives on its platform\'s network', () {
      final networks = SwapNetworks([eth, btc, atom]);

      expect(networks.networkOf(usdc), 'Ethereum');
      expect(networks.networkOf(usdcArb), 'Arbitrum');
      expect(networks.networkOf(btc), 'BTC');
      expect(networks.networkOf(iris), 'ATOM');
    });

    test('an EVM chain is named by the wallet\'s coin on it', () {
      final networks = SwapNetworks([usdc, usdcArb, eth, btc]);

      expect(networks.networkOfEvmChain(1), 'Ethereum');
      expect(networks.networkOfEvmChain(42161), isNull);
      expect(networks.networkOfEvmChain(null), isNull);
      expect(SwapNetworks.evmChainIdOf(usdc), 1);
      expect(SwapNetworks.evmChainIdOf(btc), isNull);
    });
  });
}
