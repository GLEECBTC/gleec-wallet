import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_order_book_offers.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

part 'unified_swap_quotes.dart';

/// Prices a swap across every liquidity source and ranks the results.
///
/// The wallet has two genuinely different sources and neither subsumes the
/// other: the aggregator reaches far more assets and bridges chains, while the
/// atomic orderbook is peer-to-peer and is the only route for the wallet's own
/// GLEEC and GRC-20 assets.
class UnifiedSwapRepository {
  /// Creates a repository over [sources], priced by [pricing], for the
  /// wallet's [knownAssets] of which [activatedAssets] are active.
  UnifiedSwapRepository({
    required List<SwapQuoteSource> sources,
    required SwapPricingService pricing,
    Set<AssetId> Function()? knownAssets,
    Future<Set<AssetId>> Function()? activatedAssets,
  }) : _sources = sources,
       _pricing = pricing,
       _knownAssets = knownAssets ?? (() => const {}),
       _activatedAssets = activatedAssets;

  final List<SwapQuoteSource> _sources;
  final SwapPricingService _pricing;
  final Set<AssetId> Function() _knownAssets;
  final Future<Set<AssetId>> Function()? _activatedAssets;
  SwapCatalog? _catalog;
  var _reads = 0;
  final _arrivals = StreamController<void>.broadcast();

  /// The pricing service, for callers that value amounts themselves.
  SwapPricingService get pricing => _pricing;

  /// The latest catalog: the last read, with any list that arrived after it.
  SwapCatalog? get current => _catalog;

  /// Fires when a list that arrived after its read changes [current].
  Stream<void> get arrivals => _arrivals.stream;

  /// Reads what every source can trade, and remembers it for [quote].
  ///
  /// Signed out, nothing is active, and reading that would still queue for
  /// the wallet's sign-in lock.
  Future<SwapCatalog> catalog({bool signedIn = true}) async {
    final read = ++_reads;
    final activated = signedIn ? await _readActivated() : const <AssetId>{};
    final known = {..._knownAssets(), ...?activated};
    final lists = await Future.wait(
      _sources.map(
        (source) => source
            .assets(known: known, activated: activated ?? known)
            .catchError(
              (Object _) => SwapSourceAssets(
                source: source.source,
                status: SwapCatalogStatus.unavailable,
              ),
            ),
      ),
    );
    final catalog = SwapCatalog(sources: lists, activated: activated);
    // A read that returns after a later one must not replace it.
    if (read == _reads) _catalog = catalog;
    for (final list in lists) {
      if (list.update case final update?) unawaited(_arrive(read, update));
    }
    return catalog;
  }

  Future<void> _arrive(int read, Future<SwapSourceAssets> update) async {
    final SwapSourceAssets list;
    try {
      list = await update;
    } on Object {
      return;
    }
    final current = _catalog;
    if (read != _reads || current == null) return;
    final next = current.replacing(list);
    if (next == current) return;
    _catalog = next;
    _arrivals.add(null);
  }

  Future<Set<AssetId>?> _readActivated() async {
    try {
      return await _activatedAssets?.call();
    } on Object {
      return _catalog?.activated;
    }
  }

  List<SwapQuoteSource> _sourcesFor(AssetId from, AssetId to) {
    final catalog = _catalog;
    if (catalog == null) return _sources;
    final able = catalog.support(from, to).sources;
    return [
      for (final source in _sources)
        if (able.contains(source.source)) source,
    ];
  }

  /// Whether only the order book can price [from] for [to], by the latest
  /// catalog.
  bool orderBookOnly(AssetId from, AssetId to) {
    final sources = _catalog?.support(from, to).sources;
    return sources != null &&
        sources.length == 1 &&
        sources.single == SwapLiquiditySource.atomic;
  }

  SwapOfferSource? get _offerSource {
    for (final source in _sources) {
      if (source is SwapOfferSource) return source as SwapOfferSource;
    }
    return null;
  }

  /// What the order book offers for [from] → [to]; null when unknown.
  Future<SwapOrderBookOffers?> offers(AssetId from, AssetId to) async {
    try {
      return await _offerSource?.offers(from, to);
    } on Object {
      return null;
    }
  }

  /// For each asset only the order book trades with [anchor], whether anyone
  /// offers it: bought with [anchor] when [anchorPays], sold for it otherwise.
  /// Null when nothing could be checked.
  Future<Map<AssetId, bool>?> offeredWith(
    AssetId anchor, {
    required bool anchorPays,
  }) async {
    final source = _offerSource;
    final catalog = _catalog;
    if (source == null || catalog == null) return null;
    final candidates = [
      for (final id in catalog.assets)
        if (id != anchor &&
            orderBookOnly(anchorPays ? anchor : id, anchorPays ? id : anchor))
          id,
    ];
    try {
      return await source.offered(anchor, candidates, anchorPays: anchorPays);
    } on Object {
      return null;
    }
  }

  /// Prices a swap everywhere it can be priced, at once.
  ///
  /// Sources are queried concurrently and independently: one venue being slow
  /// or broken must not withhold a price another already has. A source the
  /// catalog says cannot trade the pair is not asked at all — asking it only
  /// spends its request budget on an answer that is known in advance.
  Future<UnifiedSwapQuotes> quote(SwapQuoteRequest request) async {
    if (request.amount <= Decimal.zero) {
      return const UnifiedSwapQuotes(ranked: [], unrankable: [], failures: []);
    }
    final local = _localFailures(
      request.from,
      request.to,
      signedOut: request.signedOut,
    );
    if (local != null) {
      return UnifiedSwapQuotes(
        ranked: const [],
        unrankable: const [],
        failures: local,
      );
    }
    final able = _sourcesFor(request.from, request.to);
    final asked = [
      for (final source in able)
        if (!request.signedOut || source.pricesSignedOut) source,
    ];
    // Not asked, but reported, so the form can say a wallet adds them.
    final waiting = [
      for (final source in able)
        if (!asked.contains(source))
          SwapQuoteFailure(
            source: source.source,
            kind: SwapQuoteFailureKind.signedOut,
          ),
    ];
    if (asked.isEmpty) {
      return UnifiedSwapQuotes(
        ranked: const [],
        unrankable: const [],
        failures: waiting,
      );
    }
    await _pricing.prices.warm([
      request.from,
      request.to,
      ?request.from.parentId,
    ]);

    final results = await Future.wait(
      asked.map(
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
    failures.addAll(waiting);

    // Fee tokens can differ from either side of the swap; price them too.
    await _pricing.prices.warm([
      for (final quote in quotes)
        for (final fee in quote.fees)
          if (fee.asset != null) fee.asset!,
    ]);
    final priced = quotes.map(_pricing.price).toList();
    return rank(priced, failures);
  }

  /// The routes a comparison adds to [request]'s: each aggregator's fastest
  /// route, priced.
  Future<List<SwapQuote>> alternatives(SwapQuoteRequest request) async {
    if (_localFailures(request.from, request.to) != null) return const [];
    final routed = _sourcesFor(
      request.from,
      request.to,
    ).where((source) => source.source == SwapLiquiditySource.routed);
    final results = await Future.wait(
      routed.map(
        (source) => source
            .quote(request.withOrders(const {SwapQuoteOrder.fastest}))
            .catchError((Object _) => const <SwapQuoteResult>[]),
      ),
    );
    final quotes = [
      for (final result in results.expand((r) => r))
        if (result is SwapQuoteAvailable) result.quote,
    ];
    await _pricing.prices.warm([
      for (final quote in quotes)
        for (final fee in quote.fees)
          if (fee.asset != null) fee.asset!,
    ]);
    return quotes.map(_pricing.price).toList();
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
  /// apply. A [preferred] source is asked alone, and the others only if it
  /// cannot tell.
  Future<Map<SwapLiquiditySource, SwapMaxAmount>> maxAmounts({
    required AssetId from,
    required AssetId to,
    required Decimal balance,
    SwapLiquiditySource? preferred,
  }) async {
    Future<Map<SwapLiquiditySource, SwapMaxAmount>> ask(
      Iterable<SwapQuoteSource> sources,
    ) async {
      final entries = await Future.wait(
        sources.map((source) async {
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

    final able = _sourcesFor(from, to);
    if (preferred != null) {
      final own = await ask(able.where((s) => s.source == preferred));
      if (own.isNotEmpty) return own;
    }
    return ask(able.where((s) => s.source != preferred));
  }

  /// Failures known without asking any source; null means ask the sources.
  List<SwapQuoteFailure>? _localFailures(
    AssetId from,
    AssetId to, {
    bool signedOut = false,
  }) {
    final catalog = _catalog;
    if (catalog == null) return null;
    final support = catalog.support(from, to);
    if (!support.isSupported) {
      return [
        for (final source in _sources)
          SwapQuoteFailure(
            source: source.source,
            kind: SwapQuoteFailureKind.pairUnsupported,
          ),
      ];
    }
    // The sources asked signed out need no active coin.
    if (signedOut) return null;
    for (final asset in [from, to]) {
      if (!catalog.isActive(asset)) {
        return [
          SwapQuoteFailure(
            source: support.sources.first,
            kind: SwapQuoteFailureKind.assetInactive,
            asset: asset,
          ),
        ];
      }
    }
    return null;
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
