import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// Everything one pricing attempt produced.
class UnifiedSwapQuotes {
  const UnifiedSwapQuotes({required this.quotes, required this.rejections});

  /// Priced options, best first.
  final List<SwapQuote> quotes;

  /// Sources that could not price this swap, and why.
  ///
  /// Kept rather than discarded: when nothing can be priced, *why* is the only
  /// useful thing to tell the user, and "no aggregator lists this asset" needs
  /// very different copy from "no one is trading it right now".
  final List<SwapQuoteUnavailable> rejections;

  /// The option to present, if any.
  SwapQuote? get best => quotes.isEmpty ? null : quotes.first;

  /// Whether every source declined.
  bool get isEmpty => quotes.isEmpty;

  /// Whether the sources agree this pair simply cannot be traded here.
  ///
  /// Distinct from a transient failure, and worth its own message: retrying
  /// will not help, and the user should be steered to a different pair.
  bool get isPermanentlyUnsupported =>
      quotes.isEmpty &&
      rejections.isNotEmpty &&
      rejections.every(
        (r) => r.reason == SwapQuoteUnavailableReason.pairUnsupported,
      );
}

/// Prices a swap across every liquidity source and ranks the results.
///
/// The wallet has two genuinely different sources and neither subsumes the
/// other: the aggregator reaches far more assets and bridges chains, while the
/// atomic orderbook is peer-to-peer and is the only route for the wallet's own
/// GLEEC and GRC-20 assets, which no aggregator indexes. Asking both and
/// ranking honestly is what makes one swap screen possible.
class UnifiedSwapRepository {
  /// Creates a repository over [sources].
  UnifiedSwapRepository({required List<SwapQuoteSource> sources})
    : _sources = sources;

  final List<SwapQuoteSource> _sources;

  /// Every asset that at least one source can trade.
  Future<Set<AssetId>> tradableAssets() async {
    final results = await Future.wait(
      _sources.map((source) => source.tradableAssets()),
    );
    return results.expand((assets) => assets).toSet();
  }

  /// Which sources can trade [asset].
  ///
  /// Lets the UI explain that an asset is available but only peer-to-peer,
  /// rather than silently offering fewer options.
  Future<Set<SwapLiquiditySource>> sourcesFor(AssetId asset) async {
    final available = <SwapLiquiditySource>{};
    await Future.wait(
      _sources.map((source) async {
        final assets = await source.tradableAssets();
        if (assets.contains(asset)) available.add(source.source);
      }),
    );
    return available;
  }

  /// Prices a swap everywhere at once.
  ///
  /// Sources are queried concurrently and independently: one venue being slow
  /// or broken must not withhold a price another already has.
  Future<UnifiedSwapQuotes> quote({
    required AssetId from,
    required AssetId to,
    required Decimal amount,
  }) async {
    if (amount <= Decimal.zero) {
      return const UnifiedSwapQuotes(quotes: [], rejections: []);
    }

    final results = await Future.wait(
      _sources.map(
        (source) => source
            .quote(from: from, to: to, amount: amount)
            .catchError(
              // A source contract violation must not take down the others.
              (Object error) =>
                  SwapQuoteRejected(
                        SwapQuoteUnavailable(
                          source: source.source,
                          reason:
                              SwapQuoteUnavailableReason.temporarilyUnavailable,
                          message: error.toString(),
                        ),
                      )
                      as SwapQuoteResult,
            ),
      ),
    );

    final quotes = <SwapQuote>[];
    final rejections = <SwapQuoteUnavailable>[];
    for (final result in results) {
      switch (result) {
        case SwapQuoteAvailable(:final quote):
          quotes.add(quote);
        case SwapQuoteRejected(:final unavailable):
          rejections.add(unavailable);
      }
    }

    quotes.sort(_byGuaranteedReceive);
    return UnifiedSwapQuotes(quotes: quotes, rejections: rejections);
  }

  /// Ranks by what each option actually promises.
  ///
  /// Comparing guaranteed amounts rather than expected ones is the only fair
  /// comparison available: a routed quote's expected figure is subject to
  /// slippage while an atomic fill is not, so ranking on expectation would
  /// systematically favour the option with the looser promise.
  static int _byGuaranteedReceive(SwapQuote a, SwapQuote b) {
    final byAmount = b.guaranteedReceive.compareTo(a.guaranteedReceive);
    if (byAmount != 0) return byAmount;
    // Same promise: prefer the faster one, then the peer-to-peer one, which
    // involves no third-party contract.
    final aDuration = a.estimatedDuration ?? Duration.zero;
    final bDuration = b.estimatedDuration ?? Duration.zero;
    final byDuration = aDuration.compareTo(bDuration);
    if (byDuration != 0) return byDuration;
    if (a.source == b.source) return 0;
    return a.source == SwapLiquiditySource.atomic ? -1 : 1;
  }
}
