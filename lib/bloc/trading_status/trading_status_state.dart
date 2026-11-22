part of 'trading_status_bloc.dart';

abstract class TradingStatusState extends Equatable {
  @override
  List<Object?> get props => [isEnabled];

  bool get isEnabled =>
      this is TradingStatusLoadSuccess &&
      !(this as TradingStatusLoadSuccess).disallowedFeatures.contains(
        DisallowedFeature.trading,
      );
}

class TradingStatusInitial extends TradingStatusState {}

class TradingStatusLoadInProgress extends TradingStatusState {}

class TradingStatusLoadSuccess extends TradingStatusState {
  TradingStatusLoadSuccess({
    Set<AssetId>? disallowedAssets,
    this.tradingPolicy,
    Set<DisallowedFeature>? disallowedFeatures,
  }) : disallowedAssets = disallowedAssets ?? const <AssetId>{},
       disallowedFeatures = disallowedFeatures ?? const <DisallowedFeature>{};

  final Set<AssetId> disallowedAssets;
  final TradingAssetPolicy? tradingPolicy;
  final Set<DisallowedFeature> disallowedFeatures;

  @override
  bool get isEnabled => !disallowedFeatures.contains(DisallowedFeature.trading);

  @override
  List<Object?> get props => [
    disallowedAssets,
    disallowedFeatures,
    tradingPolicy,
  ];
}

class TradingStatusLoadFailure extends TradingStatusState {}

extension TradingStatusStateX on TradingStatusState {
  Set<AssetId> get disallowedAssetIds => this is TradingStatusLoadSuccess
      ? (this as TradingStatusLoadSuccess).disallowedAssets
      : const <AssetId>{};

  bool isAssetBlocked(AssetId? asset) {
    if (asset == null) return true;
    if (this is! TradingStatusLoadSuccess) return true;
    return (this as TradingStatusLoadSuccess).disallowedAssets.contains(asset);
  }

  bool canTradeAssets(Iterable<AssetId?> assets) {
    if (!isEnabled) return false;
    // Filter out nulls - only check assets that are actually selected
    final nonNullAssets = assets.whereType<AssetId>().toList();
    final policy = this is TradingStatusLoadSuccess
        ? (this as TradingStatusLoadSuccess).tradingPolicy
        : null;
    if (policy != null) {
      if (nonNullAssets.any((asset) => !policy.allowsAsset(asset))) {
        return false;
      }
      for (final from in nonNullAssets) {
        for (final to in nonNullAssets) {
          if (!policy.allowsPair(from.id, to.id)) return false;
        }
      }
    } else if (nonNullAssets.any((asset) => !canTradeAssetId(asset))) {
      return false;
    }
    for (final asset in nonNullAssets) {
      if (_isWalletOnlyAsset(asset)) return false;
      if (isAssetBlocked(asset)) return false;
    }
    return true;
  }

  bool _isWalletOnlyAsset(AssetId asset) {
    return isWalletOnlyTradingAssetId(asset.id);
  }
}
