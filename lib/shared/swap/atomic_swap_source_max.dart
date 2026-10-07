part of 'atomic_swap_source.dart';

/// How much Max may sell on the order book.
extension _AtomicSwapMax on AtomicSwapQuoteSource {
  Future<SwapMaxAmount?> _maxAmount(
    AssetId from,
    AssetId to,
    Decimal balance,
  ) async {
    final asked = _now();
    try {
      // KDF's own answer already keeps back the trading fee and, for a coin
      // that pays its own network fees, the fees to send its payments.
      final response = _trading
          .maxTakerVolume(coin: from.id, tradeWith: to.id)
          .then<Decimal?>(
            (response) => Decimal.tryParse(response.amount),
            onError: (Object _) => null,
          );
      final book = _readOffers(from, to);
      final max = await response;
      if (max == null) return null;
      final decimals = from.chainId.decimals;
      // KDF's figures seldom end within the asset's decimals.
      Decimal sellableOf(Decimal value) {
        final kept = value < Decimal.zero ? Decimal.zero : value;
        return decimals == null ? kept : kept.floor(scale: decimals);
      }

      var sellable = sellableOf(max > balance ? balance : max);
      final claim = await _claimFee(from, to, sellable, asked);
      final offers = await book;
      // On top of the refund gas KDF kept, though a swap pays only one of the
      // two: the overlap is Max's margin for gas rising before its quote.
      if (claim != null) sellable = sellableOf(sellable - claim);
      // More than the largest offer never fills; with no offers, Max still
      // shows what could be sold.
      final fillable = offers?.largestUpTo(sellable, scale: decimals);
      return SwapMaxAmount(
        amount: fillable ?? sellable,
        reservedForFees: balance > sellable ? balance - sellable : Decimal.zero,
        feeAsset: from,
        reserveCovers: from.parentId == null
            ? SwapMaxReserve.tradingAndNetworkFees
            : SwapMaxReserve.tradingFee,
        offerLimit: fillable != null && fillable < sellable,
        coversRefund: true,
      );
    } on Object {
      return null;
    }
  }

  /// The gas [from] pays to claim [to], a token on [from]'s own network.
  /// KDF's Max leaves it out, so selling all of that Max could leave too
  /// little to claim what arrives.
  ///
  /// Only a preimage reports it, and its fees depend on neither the price nor
  /// the offers: it is priced so the order receives KDF's own minimum of [to].
  /// Null when [from] does not pay it, or it cannot be read before
  /// [AtomicSwapQuoteSource.claimFeeDeadline] has passed since [asked].
  Future<Decimal?> _claimFee(
    AssetId from,
    AssetId to,
    Decimal volume,
    DateTime asked,
  ) async {
    if (to.parentId?.id != from.id || volume <= Decimal.zero) return null;
    final left =
        AtomicSwapQuoteSource.claimFeeDeadline - _now().difference(asked);
    if (left <= Duration.zero) return null;

    Future<Decimal?> read() async {
      final minimum = await minimumAmount(from: to);
      if (minimum == null || minimum <= Decimal.zero) return null;
      final price = (minimum / volume).toDecimal(
        scaleOnInfinitePrecision: 18,
        toBigInt: (value) => value.ceil(),
      );
      final preimage = await _trading.tradePreimage(
        base: from.id,
        rel: to.id,
        swapMethod: SwapMethod.sell,
        volume: volume.toString(),
        price: price.toString(),
      );
      final fee = preimage.relCoinFee;
      if (fee == null || fee.coin != from.id || fee.paidFromTradingVol) {
        return null;
      }
      return Decimal.tryParse(fee.amount);
    }

    try {
      return await read().timeout(
        left < AtomicSwapQuoteSource.claimFeeTimeout
            ? left
            : AtomicSwapQuoteSource.claimFeeTimeout,
      );
    } on Object {
      return null;
    }
  }
}
