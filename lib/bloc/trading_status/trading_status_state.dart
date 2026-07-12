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
    Set<DisallowedFeature>? disallowedFeatures,
  }) : disallowedAssets = disallowedAssets ?? const <AssetId>{},
       disallowedFeatures = disallowedFeatures ?? const <DisallowedFeature>{};

  final Set<AssetId> disallowedAssets;
  final Set<DisallowedFeature> disallowedFeatures;

  @override
  bool get isEnabled => !disallowedFeatures.contains(DisallowedFeature.trading);

  @override
  List<Object?> get props => [disallowedAssets, disallowedFeatures];
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
    final nonNullAssets = assets.whereType<AssetId>();
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
