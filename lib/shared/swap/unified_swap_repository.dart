import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

/// Everything one pricing attempt produced.
class UnifiedSwapQuotes extends Equatable {
  const UnifiedSwapQuotes({
    required this.ranked,
    required this.unrankable,
    required this.failures,
  });

  /// Options that could be compared on net return, best first.
  final List<SwapQuote> ranked;

  /// Options missing a price for some cost, so they cannot be compared
  /// honestly. Kept apart: a user may still choose one, deliberately.
  final List<SwapQuote> unrankable;

  /// Sources that could not price this swap, and why.
  ///
  /// Kept rather than discarded: when nothing can be priced, *why* is the only
  /// useful thing to tell the user, and "no aggregator lists this asset" needs
  /// very different copy from "no one is trading it right now".
  final List<SwapQuoteFailure> failures;

  /// Every option, ranked ones first.
  List<SwapQuote> get options => [...ranked, ...unrankable];

  /// Whether any option exists.
  bool get isEmpty => ranked.isEmpty && unrankable.isEmpty;

  /// The option to preselect, or null when the user must choose.
  ///
  /// The best ranked option; a lone unrankable option when it is the only
  /// one; and nothing when several options exist and none can be ranked —
  /// picking one silently would be a ranking by another name.
  SwapQuote? get preselected {
    if (ranked.isNotEmpty) return ranked.first;
    if (unrankable.length == 1) return unrankable.first;
    return null;
  }

  /// Whether "best net return" may be claimed for the top option: only when
  /// at least two options were comparable.
  bool get canClaimBestNetReturn => ranked.length >= 2;

  /// Whether several options exist, so comparison is worth offering.
  bool get hasAlternatives => options.length > 1;

  /// The failure that best explains an empty result, preferring the one with
  /// the most useful next step.
  SwapQuoteFailure? get primaryFailure {
    if (failures.isEmpty) return null;
    const priority = [
      SwapQuoteFailureKind.tradingBlocked,
      SwapQuoteFailureKind.clockInvalid,
      SwapQuoteFailureKind.assetInactive,
      SwapQuoteFailureKind.insufficientFunds,
      SwapQuoteFailureKind.belowMinimum,
      SwapQuoteFailureKind.aboveMaximum,
      SwapQuoteFailureKind.invalidAmount,
      SwapQuoteFailureKind.unsupportedSigner,
      SwapQuoteFailureKind.rateLimited,
      SwapQuoteFailureKind.timeout,
      SwapQuoteFailureKind.serviceError,
      SwapQuoteFailureKind.noRoute,
      SwapQuoteFailureKind.notConfigured,
      SwapQuoteFailureKind.pairUnsupported,
      SwapQuoteFailureKind.unknown,
    ];
    final sorted = [...failures]
      ..sort(
        (a, b) => priority.indexOf(a.kind).compareTo(priority.indexOf(b.kind)),
      );
    return sorted.first;
  }

  /// Whether every source agrees this pair simply cannot be traded here.
  bool get isPermanentlyUnsupported =>
      isEmpty && failures.isNotEmpty && failures.every((f) => f.isPermanent);

  /// The option with [id], if it is still on offer.
  SwapQuote? byId(String id) {
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }

  @override
  List<Object?> get props => [ranked, unrankable, failures];
}

/// Prices a swap across every liquidity source and ranks the results.
///
/// The wallet has two genuinely different sources and neither subsumes the
/// other: the aggregator reaches far more assets and bridges chains, while the
/// atomic orderbook is peer-to-peer and is the only route for the wallet's own
/// GLEEC and GRC-20 assets.
class UnifiedSwapRepository {
  /// Creates a repository over [sources], priced by [pricing].
  UnifiedSwapRepository({
    required List<SwapQuoteSource> sources,
    required SwapPricingService pricing,
  }) : _sources = sources,
       _pricing = pricing;

  final List<SwapQuoteSource> _sources;
  final SwapPricingService _pricing;

  /// The pricing service, for callers that value amounts themselves.
  SwapPricingService get pricing => _pricing;

  /// Every asset that at least one source can trade.
  Future<Set<AssetId>> tradableAssets() async {
    final results = await Future.wait(
      _sources.map(
        (source) =>
            source.tradableAssets().catchError((Object _) => <AssetId>{}),
      ),
    );
    return results.expand((assets) => assets).toSet();
  }

  /// Which sources can trade [asset].
  Future<Set<SwapLiquiditySource>> sourcesFor(AssetId asset) async {
    final available = <SwapLiquiditySource>{};
    await Future.wait(
      _sources.map((source) async {
        final assets = await source.tradableAssets().catchError(
          (Object _) => <AssetId>{},
        );
        if (assets.contains(asset)) available.add(source.source);
      }),
    );
    return available;
  }

  /// Prices a swap everywhere at once.
  ///
  /// Sources are queried concurrently and independently: one venue being slow
  /// or broken must not withhold a price another already has.
  Future<UnifiedSwapQuotes> quote(SwapQuoteRequest request) async {
    if (request.amount <= Decimal.zero) {
      return const UnifiedSwapQuotes(ranked: [], unrankable: [], failures: []);
    }
    await _pricing.prices.warm([
      request.from,
      request.to,
      ?request.from.parentId,
    ]);

    final results = await Future.wait(
      _sources.map(
        (source) => source
            .quote(request)
            .catchError(
              // A source contract violation must not take down the others.
              (Object error) => <SwapQuoteResult>[
                SwapQuoteRejected(
                  SwapQuoteFailure(
                    source: source.source,
                    kind: SwapQuoteFailureKind.unknown,
                    detail: error.toString(),
                  ),
                ),
              ],
            ),
      ),
    );

    final quotes = <SwapQuote>[];
    final failures = <SwapQuoteFailure>[];
    for (final result in results.expand((r) => r)) {
      switch (result) {
        case SwapQuoteAvailable(:final quote):
          quotes.add(quote);
        case SwapQuoteRejected(:final failure):
          failures.add(failure);
      }
    }

    // Fee tokens can differ from either side of the swap; price them too.
    await _pricing.prices.warm([
      for (final quote in quotes)
        for (final fee in quote.fees)
          if (fee.asset != null) fee.asset!,
    ]);
    final priced = quotes.map(_pricing.price).toList();
    return rank(priced, failures);
  }

  /// Prices [quote] again on the same source and route.
  Future<SwapQuoteResult> requote(SwapQuote quote) async {
    final source = _sources.where((s) => s.source == quote.source).firstOrNull;
    if (source == null) {
      return SwapQuoteRejected(
        SwapQuoteFailure(
          source: quote.source,
          kind: SwapQuoteFailureKind.unknown,
        ),
      );
    }
    final SwapQuoteResult result;
    try {
      result = await source.requote(quote);
    } on Object catch (error) {
      return SwapQuoteRejected(
        SwapQuoteFailure(
          source: quote.source,
          kind: SwapQuoteFailureKind.unknown,
          detail: error.toString(),
        ),
      );
    }
    return switch (result) {
      SwapQuoteAvailable(quote: final fresh) => SwapQuoteAvailable(
        _pricing.price(fresh),
      ),
      SwapQuoteRejected() => result,
    };
  }

  /// The largest amount of [from] that can be sold for [to], per source.
  ///
  /// Each source keeps back what its own fees need; the caller picks which to
  /// apply.
  Future<Map<SwapLiquiditySource, SwapMaxAmount>> maxAmounts({
    required AssetId from,
    required AssetId to,
    required Decimal balance,
  }) async {
    final entries = await Future.wait(
      _sources.map((source) async {
        final max = await source
            .maxAmount(from: from, to: to, balance: balance)
            .catchError((Object _) => null);
        return MapEntry(source.source, max);
      }),
    );
    return {
      for (final entry in entries)
        if (entry.value != null) entry.key: entry.value!,
    };
  }

  /// Ranks [quotes] by what each actually promises.
  ///
  /// Net return — the guaranteed minimum's value less the costs it does not
  /// already account for — is the only fair comparison: a routed quote's
  /// expected figure is subject to slippage while an atomic fill is not, and
  /// comparing headline amounts would favour the looser promise. Ties go to
  /// the faster option, then to peer-to-peer, which involves no third-party
  /// contract.
  static UnifiedSwapQuotes rank(
    List<SwapQuote> quotes,
    List<SwapQuoteFailure> failures,
  ) {
    final ranked = quotes.where((q) => q.isRankable).toList()
      ..sort((a, b) {
        final byNet = b.netReturnUsd!.compareTo(a.netReturnUsd!);
        if (byNet != 0) return byNet;
        return _tieBreak(a, b);
      });
    final unrankable = quotes.where((q) => !q.isRankable).toList()
      ..sort((a, b) {
        final byMinimum = b.guaranteedReceive.compareTo(a.guaranteedReceive);
        if (byMinimum != 0) return byMinimum;
        return _tieBreak(a, b);
      });
    return UnifiedSwapQuotes(
      ranked: ranked,
      unrankable: unrankable,
      failures: failures,
    );
  }

  static int _tieBreak(SwapQuote a, SwapQuote b) {
    final aDuration = a.estimatedDuration ?? Duration.zero;
    final bDuration = b.estimatedDuration ?? Duration.zero;
    final byDuration = aDuration.compareTo(bDuration);
    if (byDuration != 0) return byDuration;
    if (a.source == b.source) return 0;
    return a.source == SwapLiquiditySource.atomic ? -1 : 1;
  }
}
