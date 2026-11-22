part of 'asset_overview_bloc.dart';

abstract class AssetOverviewState extends Equatable {
  const AssetOverviewState();

  @override
  List<Object?> get props => [];
}

class AssetOverviewInitial extends AssetOverviewState {
  const AssetOverviewInitial();
}

class AssetOverviewLoadInProgress extends AssetOverviewState {
  const AssetOverviewLoadInProgress();
}

class AssetOverviewLoadSuccess extends AssetOverviewState {
  const AssetOverviewLoadSuccess({
    required this.totalValue,
    required this.totalInvestment,
    required this.profitAmount,
    required this.investmentReturnPercentage,
  });

  final EntityWithValue totalValue;
  final EntityWithValue totalInvestment;
  final EntityWithValue profitAmount;
  final double investmentReturnPercentage;

  @override
  List<Object?> get props => [
    totalValue,
    totalInvestment,
    profitAmount,
    investmentReturnPercentage,
  ];
}

class AssetOverviewLoadFailure extends AssetOverviewState {
  const AssetOverviewLoadFailure({required this.error});

  final String error;

  @override
  List<Object?> get props => [error];
}

class PortfolioAssetsOverviewLoadSuccess extends AssetOverviewState {
  const PortfolioAssetsOverviewLoadSuccess({
    required this.selectedAssetIds,
    required this.assetPortionPercentages,
    required this.totalInvestment,
    required this.totalValue,
    required this.profitAmount,
    required this.profitIncreasePercentage,
    this.excludedAssetIds = const [],
  });

  /// The assets the totals cover.
  final List<String> selectedAssetIds;
  final Map<String, double> assetPortionPercentages;
  final EntityWithValue totalInvestment;
  final EntityWithValue totalValue;
  final EntityWithValue profitAmount;
  final double profitIncreasePercentage;

  /// Active assets whose profit/loss could not be computed. They are left out
  /// of every total rather than counted as zero.
  final List<String> excludedAssetIds;

  int get assetsCount => selectedAssetIds.length;

  @override
  List<Object?> get props => [
    selectedAssetIds,
    assetPortionPercentages,
    totalInvestment,
    totalValue,
    profitAmount,
    profitIncreasePercentage,
    excludedAssetIds,
  ];
}

/// Why a load left no portfolio totals to show.
enum AssetOverviewUnavailableReason {
  /// None of the wallet's assets is active yet.
  noActiveAssets,

  /// None of the active assets could be valued.
  noAssetValued,

  /// The session's wallet identity could not be read, so results can neither
  /// be stored nor looked up for this wallet.
  walletIdentity,

  /// The load failed for another reason.
  loadFailed,
}

/// The portfolio totals are not known. Unlike [AssetOverviewInitial] nothing
/// is loading: the next refresh may find them.
class PortfolioAssetsOverviewUnavailable extends AssetOverviewState {
  const PortfolioAssetsOverviewUnavailable({required this.reason});

  final AssetOverviewUnavailableReason reason;

  @override
  List<Object?> get props => [reason];
}
