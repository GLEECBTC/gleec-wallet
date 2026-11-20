part of 'profit_loss_bloc.dart';

sealed class ProfitLossState extends Equatable {
  const ProfitLossState({required this.selectedPeriod});

  final Duration selectedPeriod;

  @override
  List<Object> get props => [selectedPeriod];
}

final class ProfitLossInitial extends ProfitLossState {
  const ProfitLossInitial() : super(selectedPeriod: const Duration(hours: 1));
}

final class PortfolioProfitLossChartLoadInProgress extends ProfitLossState {
  const PortfolioProfitLossChartLoadInProgress({required super.selectedPeriod});
}

final class PortfolioProfitLossChartLoadSuccess extends ProfitLossState {
  const PortfolioProfitLossChartLoadSuccess({
    required this.profitLossChart,
    required this.totalValue,
    required this.percentageIncrease,
    required this.coins,
    required this.fiatCurrency,
    required this.walletId,
    required super.selectedPeriod,
    this.excludedAssetIds = const [],
    this.isUpdating = false,
  });

  final List<Point<double>> profitLossChart;
  final double totalValue;
  final double percentageIncrease;
  final List<Coin> coins;
  final String fiatCurrency;
  final String walletId;
  final bool isUpdating;

  /// Assets in [coins] whose profit/loss could not be computed. The chart and
  /// totals cover the others; these are left out rather than counted as zero.
  final List<String> excludedAssetIds;

  PortfolioProfitLossChartLoadSuccess copyWith({
    Duration? selectedPeriod,
    bool? isUpdating,
  }) => PortfolioProfitLossChartLoadSuccess(
    profitLossChart: profitLossChart,
    totalValue: totalValue,
    percentageIncrease: percentageIncrease,
    coins: coins,
    fiatCurrency: fiatCurrency,
    walletId: walletId,
    selectedPeriod: selectedPeriod ?? this.selectedPeriod,
    excludedAssetIds: excludedAssetIds,
    isUpdating: isUpdating ?? this.isUpdating,
  );

  @override
  List<Object> get props => [
    profitLossChart,
    totalValue,
    percentageIncrease,
    coins,
    fiatCurrency,
    selectedPeriod,
    walletId,
    excludedAssetIds,
    isUpdating,
  ];
}

/// Why a load left no profit/loss to show.
enum ProfitLossUnavailableReason {
  /// None of the requested assets is active yet.
  noActiveAssets,

  /// None of the requested assets could be valued.
  noAssetValued,

  /// The session's wallet identity could not be read, so results can neither
  /// be stored nor looked up for this wallet.
  walletIdentity,

  /// The load failed for another reason.
  loadFailed,
}

final class ProfitLossLoadFailure extends ProfitLossState {
  const ProfitLossLoadFailure({
    required this.reason,
    required super.selectedPeriod,
  });

  final ProfitLossUnavailableReason reason;

  @override
  List<Object> get props => [reason, selectedPeriod];
}

final class PortfolioProfitLossChartUnsupported extends ProfitLossState {
  const PortfolioProfitLossChartUnsupported({required super.selectedPeriod});
}
