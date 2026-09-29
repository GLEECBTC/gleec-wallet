part of 'atomic_swap_source.dart';

/// What the order book offers, read before any swap is priced.
extension _AtomicSwapOffers on AtomicSwapQuoteSource {
  /// Reads only the pair's own book: KDF follows every pair it is asked for
  /// from then on, so this is never fanned out over candidates.
  Future<SwapOrderBookOffers?> _readOffers(AssetId from, AssetId to) async {
    if (!canTrade(from) || !canTrade(to)) return null;
    try {
      final minimum = minimumAmount(from: from);
      final book = await _trading.getOrderbook(base: from.id, rel: to.id);
      return SwapOrderBookOffers.fromBids(book.bids, floor: await minimum);
    } on Object {
      return null;
    }
  }

  /// Counts orders with `orderbook_depth`, which follows no pair and whose
  /// relay answers every pair, so an asset nobody trades reads as none rather
  /// than as no answer. The user's own orders count here.
  Future<Map<AssetId, bool>?> _countOffered(
    AssetId anchor,
    Iterable<AssetId> candidates, {
    required bool anchorPays,
  }) async {
    if (!canTrade(anchor)) return null;
    final pairs = [
      for (final id in candidates)
        // One wallet-only coin fails KDF's whole request.
        if (id != anchor && canTrade(id))
          (
            id,
            anchorPays
                ? OrderbookPair(base: anchor.id, rel: id.id)
                : OrderbookPair(base: id.id, rel: anchor.id),
          ),
    ];
    if (pairs.isEmpty) return const {};

    Future<Map<AssetId, bool>?> count(
      List<(AssetId, OrderbookPair)> batch,
    ) async {
      try {
        final response = await _trading
            .orderbookDepth(pairs: [for (final (_, pair) in batch) pair])
            .timeout(AtomicSwapQuoteSource.offeredTimeout);
        // Answers are matched to the requested tickers; KDF also echoes a
        // pair it trades under another ticker.
        final bids = {
          for (final depth in response.depth)
            (depth.base, depth.rel): depth.bids,
        };
        return {
          for (final (id, pair) in batch)
            if (bids[(pair.base, pair.rel)] case final int count) id: count > 0,
        };
      } on Object {
        return null;
      }
    }

    final answers = await Future.wait([
      for (var i = 0; i < pairs.length; i += AtomicSwapQuoteSource.offeredBatch)
        count(
          pairs.sublist(
            i,
            i + AtomicSwapQuoteSource.offeredBatch < pairs.length
                ? i + AtomicSwapQuoteSource.offeredBatch
                : pairs.length,
          ),
        ),
    ]);
    if (answers.every((answer) => answer == null)) return null;
    return {for (final answer in answers) ...?answer};
  }
}
