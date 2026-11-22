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
  });

  final List<String> selectedAssetIds;
  final Map<String, double> assetPortionPercentages;
  final EntityWithValue totalInvestment;
  final EntityWithValue totalValue;
  final EntityWithValue profitAmount;
  final double profitIncreasePercentage;

  int get assetsCount => selectedAssetIds.length;

  @override
  List<Object?> get props => [
        selectedAssetIds,
        assetPortionPercentages,
        totalInvestment,
        totalValue,
        profitAmount,
        profitIncreasePercentage,
      ];
}
