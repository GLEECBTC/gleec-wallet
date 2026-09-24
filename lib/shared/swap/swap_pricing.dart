import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// Where US-dollar prices come from.
///
/// Synchronous reads from a cache that [warm] fills, so a quote can be priced
/// and ranked without an await per asset, and a price that is not known yet
/// reads as unknown rather than stalling the form.
abstract interface class SwapPriceSource {
  /// The last known USD price of one unit of [asset], or null.
  Decimal? usdPrice(AssetId asset);

  /// Fetches prices for [assets] into the cache. Never throws.
  Future<void> warm(Iterable<AssetId> assets);
}

/// Prices from the SDK's market data.
class SdkSwapPriceSource implements SwapPriceSource {
  SdkSwapPriceSource(this._marketData);

  final MarketDataManager _marketData;

  @override
  Decimal? usdPrice(AssetId asset) {
    try {
      return _marketData.priceIfKnown(asset);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> warm(Iterable<AssetId> assets) async {
    await Future.wait([
      for (final asset in assets.toSet())
        _marketData
            .maybeFiatPrice(asset)
            .then<void>((_) {}, onError: (Object _) {}),
    ]);
  }
}

/// Attaches US-dollar figures to quotes, and nothing more.
///
/// Honest by construction: a cost whose price is unknown stays unknown and
/// marks the pricing incomplete, so no total or ranking is ever built from the
/// costs that happen to be priced.
class SwapPricingService {
  const SwapPricingService(this._prices);

  final SwapPriceSource _prices;

  /// The price source, for callers that need to warm it.
  SwapPriceSource get prices => _prices;

  /// USD value of [amount] of [asset], or null.
  Decimal? usdValue(AssetId? asset, Decimal amount) {
    if (asset == null) return null;
    final price = _prices.usdPrice(asset);
    return price == null ? null : amount * price;
  }

  /// [quote] with its fees and headline amounts priced.
  SwapQuote price(SwapQuote quote) {
    final fees = [
      for (final fee in quote.fees)
        fee.usdValue != null
            ? fee
            : fee.withUsd(usdValue(fee.asset, fee.amount)),
    ];

    Decimal? sum(Iterable<SwapFeeComponent> items) {
      var total = Decimal.zero;
      for (final fee in items) {
        final usd = fee.usdValue;
        if (usd == null) return null;
        total += usd;
      }
      return total;
    }

    final network = sum(
      fees.where(
        (fee) =>
            fee.kind == SwapFeeKind.network ||
            fee.kind == SwapFeeKind.approvalNetwork,
      ),
    );
    final approval = sum(
      fees.where((fee) => fee.kind == SwapFeeKind.approvalNetwork),
    );
    final swap = sum(
      fees.where(
        (fee) => fee.kind == SwapFeeKind.swap || fee.kind == SwapFeeKind.dexFee,
      ),
    );

    return quote.withPricing(
      SwapQuotePricing(
        payUsd: usdValue(quote.from, quote.sellAmount),
        expectedUsd: usdValue(quote.to, quote.expectedReceive),
        minimumUsd: usdValue(quote.to, quote.guaranteedReceive),
        networkCostUsd: network,
        approvalNetworkCostUsd: approval,
        swapCostUsd: swap,
        isComplete: network != null && swap != null,
      ),
      fees: fees,
    );
  }
}
