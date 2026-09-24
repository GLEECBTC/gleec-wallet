import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// How current a source's list of assets is.
enum SwapCatalogStatus {
  /// Read just now.
  fresh,

  /// The latest read failed; the list is the last one that loaded.
  stale,

  /// Nothing has loaded; the list is the wallet's own best guess.
  unavailable,
}

/// What one liquidity source can trade.
class SwapSourceAssets extends Equatable {
  const SwapSourceAssets({
    required this.source,
    this.quotable = const {},
    this.onceActive = const {},
    this.status = SwapCatalogStatus.fresh,
  });

  /// Which source this is.
  final SwapLiquiditySource source;

  /// Activated assets the source can price now.
  final Set<AssetId> quotable;

  /// Assets the source should be able to price once they are activated.
  ///
  /// A best guess from what the wallet knows about each asset; the source
  /// confirms it after activation.
  final Set<AssetId> onceActive;

  /// How current [quotable] is.
  final SwapCatalogStatus status;

  /// Whether the source can trade [asset], now or once it is active.
  bool supports(AssetId asset) =>
      quotable.contains(asset) || onceActive.contains(asset);

  @override
  List<Object?> get props => [source, quotable, onceActive, status];
}

/// Why no source can trade a pair.
enum SwapPairGap {
  /// [SwapPairSupport.limitingAsset] cannot be swapped in this wallet.
  notTradable,

  /// [SwapPairSupport.limitingAsset] trades only on the order book, where
  /// [SwapPairSupport.routesOnlyAsset] is not listed, and cross-network
  /// routes do not reach it.
  sourcesDisjoint,
}

/// Which sources can price a pair, or why none can.
class SwapPairSupport extends Equatable {
  const SwapPairSupport({
    this.sources = const {},
    this.gap,
    this.limitingAsset,
    this.routesOnlyAsset,
    this.routesUnavailableFor,
  });

  /// Sources that can price the pair, once both assets are active.
  final Set<SwapLiquiditySource> sources;

  /// Why no source can, when none can.
  final SwapPairGap? gap;

  /// For a [gap]: the asset that cannot be swapped at all, or the one that
  /// trades only on the order book.
  final AssetId? limitingAsset;

  /// For [SwapPairGap.sourcesDisjoint]: the asset only cross-network routes
  /// can trade.
  final AssetId? routesOnlyAsset;

  /// When only the order book can price the pair although one asset is
  /// routable: the asset cross-network routes cannot reach. Explains why no
  /// cross-network option appears.
  final AssetId? routesUnavailableFor;

  /// Whether some source can price the pair.
  bool get isSupported => sources.isNotEmpty;

  @override
  List<Object?> get props => [
    sources,
    gap,
    limitingAsset,
    routesOnlyAsset,
    routesUnavailableFor,
  ];
}

/// Everything the swap surface can offer, across sources.
class SwapCatalog extends Equatable {
  const SwapCatalog({this.sources = const [], this.activated});

  /// Nothing loaded yet.
  static const empty = SwapCatalog();

  /// Each source's assets.
  final List<SwapSourceAssets> sources;

  /// Assets activated in the wallet when the catalog was read. Null when
  /// that could not be read; every asset then counts as active, and KDF
  /// answers for any that is not.
  final Set<AssetId>? activated;

  /// [source]'s assets, when it reported any.
  SwapSourceAssets? of(SwapLiquiditySource source) {
    for (final assets in sources) {
      if (assets.source == source) return assets;
    }
    return null;
  }

  /// Every asset some source can trade, active or not.
  Set<AssetId> get assets => {
    for (final source in sources) ...source.quotable,
    for (final source in sources) ...source.onceActive,
  };

  /// Whether [asset] is activated.
  bool isActive(AssetId asset) => activated?.contains(asset) ?? true;

  /// Whether some source's list could not be refreshed.
  bool get isIncomplete =>
      sources.any((source) => source.status != SwapCatalogStatus.fresh);

  /// Which sources can price [from] for [to], or why none can.
  SwapPairSupport support(AssetId from, AssetId to) {
    final able = {
      for (final source in sources)
        if (source.supports(from) && source.supports(to)) source.source,
    };
    final routed = of(SwapLiquiditySource.routed);
    AssetId? routesUnavailableFor;
    if (routed != null && !able.contains(SwapLiquiditySource.routed)) {
      final fromRoutable = routed.supports(from);
      if (fromRoutable != routed.supports(to)) {
        routesUnavailableFor = fromRoutable ? to : from;
      }
    }
    if (able.isNotEmpty) {
      return SwapPairSupport(
        sources: able,
        routesUnavailableFor: routesUnavailableFor,
      );
    }

    final all = assets;
    for (final asset in [from, to]) {
      if (!all.contains(asset)) {
        return SwapPairSupport(
          gap: SwapPairGap.notTradable,
          limitingAsset: asset,
        );
      }
    }
    // Both assets trade somewhere, just never on the same source: one only
    // on the order book, the other only through cross-network routes.
    final atomic = of(SwapLiquiditySource.atomic);
    final orderBookOnly = (atomic?.supports(from) ?? false) ? from : to;
    return SwapPairSupport(
      gap: SwapPairGap.sourcesDisjoint,
      limitingAsset: orderBookOnly,
      routesOnlyAsset: orderBookOnly == from ? to : from,
    );
  }

  @override
  List<Object?> get props => [sources, activated];
}
