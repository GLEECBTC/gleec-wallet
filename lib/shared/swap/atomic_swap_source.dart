import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/trading/trading_asset_policy.dart';

/// What executing an atomic quote needs, carried on [SwapQuote.payload].
class AtomicSwapPlan {
  const AtomicSwapPlan({
    required this.base,
    required this.rel,
    required this.volume,
    required this.price,
  });

  /// The asset being sold.
  final AssetId base;

  /// The asset being bought.
  final AssetId rel;

  /// How much of [base] to sell.
  final Decimal volume;

  /// The worst price accepted, in [rel] per [base].
  final Decimal price;
}

/// Prices swaps against KDF's own atomic-swap orderbook.
///
/// This is the only route for assets no aggregator lists — GLEEC and the
/// GRC-20 tokens most of all, since the Gleec chain is not indexed by any of
/// them. A swap screen that offered only routed liquidity could not trade the
/// wallet's own native asset.
class AtomicSwapQuoteSource implements SwapQuoteSource {
  /// Creates a source backed by the SDK's trading manager.
  AtomicSwapQuoteSource({
    required TradingManager trading,
    required Future<Set<AssetId>> Function() activatedAssets,
  }) : _trading = trading,
       _activatedAssets = activatedAssets;

  final TradingManager _trading;
  final Future<Set<AssetId>> Function() _activatedAssets;

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.atomic;

  @override
  Future<Set<AssetId>> tradableAssets() async {
    final activated = await _activatedAssets();
    // Wallet-only assets are excluded here rather than at the call site, so
    // every entry point inherits the same rule. GasFree custody-backed
    // balances are in that set: DEX settlement spends the standard EOA, which
    // does not hold them.
    return activated.where((asset) => canTradeAssetId(asset)).toSet();
  }

  @override
  Future<SwapQuoteResult> quote({
    required AssetId from,
    required AssetId to,
    required Decimal amount,
  }) async {
    if (!canTradeAssetId(from) || !canTradeAssetId(to)) {
      return const SwapQuoteRejected(
        SwapQuoteUnavailable(
          source: SwapLiquiditySource.atomic,
          reason: SwapQuoteUnavailableReason.pairUnsupported,
        ),
      );
    }

    try {
      final book = await _trading.getOrderbook(base: from.id, rel: to.id);

      // Selling `base` means filling the orders that are buying it — the bids,
      // best price first. Walking the asks here would price the opposite
      // trade and quietly overstate what the user receives.
      final levels =
          book.bids
              .map(
                (bid) => (
                  price: _decimalOf(bid.price),
                  volume: _decimalOf(bid.baseMaxVolume),
                ),
              )
              .where((level) => level.price != null && level.volume != null)
              .map((level) => (price: level.price!, volume: level.volume!))
              .toList()
            ..sort((a, b) => b.price.compareTo(a.price));

      if (levels.isEmpty) {
        return const SwapQuoteRejected(
          SwapQuoteUnavailable(
            source: SwapLiquiditySource.atomic,
            reason: SwapQuoteUnavailableReason.noLiquidity,
          ),
        );
      }

      var remaining = amount;
      var receive = Decimal.zero;
      var worstPrice = levels.first.price;

      for (final level in levels) {
        if (remaining <= Decimal.zero) break;
        final take = remaining < level.volume ? remaining : level.volume;
        receive += take * level.price;
        remaining -= take;
        worstPrice = level.price;
      }

      if (remaining > Decimal.zero) {
        // The book cannot absorb the whole order. Returning a partial fill as
        // if it were a quote would show a receive amount for an order that
        // cannot be placed at this size.
        return const SwapQuoteRejected(
          SwapQuoteUnavailable(
            source: SwapLiquiditySource.atomic,
            reason: SwapQuoteUnavailableReason.noLiquidity,
          ),
        );
      }

      final costs = await _costsFor(
        base: from,
        rel: to,
        volume: amount,
        price: worstPrice,
      );

      return SwapQuoteAvailable(
        SwapQuote(
          source: SwapLiquiditySource.atomic,
          from: from,
          to: to,
          sellAmount: amount,
          expectedReceive: receive,
          // An atomic taker order fills at the maker's price or not at all, so
          // the amount is not subject to slippage the way a routed swap is.
          guaranteedReceive: receive,
          costs: costs,
          hasUndisclosedCosts: costs.isEmpty,
          providerLabel: null,
          quotedAt: DateTime.now(),
          payload: AtomicSwapPlan(
            base: from,
            rel: to,
            volume: amount,
            price: worstPrice,
          ),
        ),
      );
    } on Object catch (error) {
      return SwapQuoteRejected(
        SwapQuoteUnavailable(
          source: SwapLiquiditySource.atomic,
          reason: SwapQuoteUnavailableReason.temporarilyUnavailable,
          message: error.toString(),
        ),
      );
    }
  }

  /// Fees for the order, from KDF's own preimage.
  ///
  /// Best-effort: a preimage failure should not hide an otherwise valid price,
  /// so the quote is still returned and flags its costs as undisclosed.
  Future<List<SwapQuoteCost>> _costsFor({
    required AssetId base,
    required AssetId rel,
    required Decimal volume,
    required Decimal price,
  }) async {
    try {
      final preimage = await _trading.tradePreimage(
        base: base.id,
        rel: rel.id,
        swapMethod: SwapMethod.sell,
        volume: volume.toString(),
        price: price.toString(),
      );
      final fees = preimage.totalFees;
      return [
        for (final fee in fees)
          SwapQuoteCost(
            label: 'Network fee',
            amount: Decimal.tryParse(fee.amount) ?? Decimal.zero,
            tokenLabel: fee.coin,
            isDeductedFromReceive: false,
          ),
      ];
    } on Object {
      return const [];
    }
  }

  /// Reads a decimal out of KDF's numeric envelope.
  ///
  /// Prices arrive as `{decimal, fraction, rational}`; the decimal string is
  /// the one to trust for display and arithmetic here.
  static Decimal? _decimalOf(NumericValue? value) =>
      value == null ? null : Decimal.tryParse(value.decimal);
}
