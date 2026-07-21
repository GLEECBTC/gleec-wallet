part of 'market_maker_trade_form_bloc.dart';

sealed class MarketMakerTradeFormEvent extends Equatable {
  const MarketMakerTradeFormEvent();

  @override
  List<Object?> get props => [];
}

class MarketMakerTradeFormSellCoinChanged extends MarketMakerTradeFormEvent {
  const MarketMakerTradeFormSellCoinChanged(this.sellCoin);

  final Coin? sellCoin;

  @override
  List<Object?> get props => [sellCoin];
}

class MarketMakerTradeFormBuyCoinChanged extends MarketMakerTradeFormEvent {
  const MarketMakerTradeFormBuyCoinChanged(this.buyCoin);

  final Coin? buyCoin;

  @override
  List<Object?> get props => [buyCoin];
}

class MarketMakerTradeFormTradeVolumeChanged extends MarketMakerTradeFormEvent {
  const MarketMakerTradeFormTradeVolumeChanged({
    required this.minimumTradeVolume,
    required this.maximumTradeVolume,
  });

  final double minimumTradeVolume;
  final double maximumTradeVolume;

  @override
  List<Object> get props => [minimumTradeVolume, maximumTradeVolume];
}

class MarketMakerTradeFormTradeMarginChanged extends MarketMakerTradeFormEvent {
  const MarketMakerTradeFormTradeMarginChanged(this.tradeMargin);

  final String tradeMargin;

  @override
  List<Object> get props => [tradeMargin];
}

class MarketMakerTradeFormUpdateIntervalChanged
    extends MarketMakerTradeFormEvent {
  const MarketMakerTradeFormUpdateIntervalChanged(this.updateInterval);

  final String updateInterval;

  @override
  List<Object> get props => [updateInterval];
}

class MarketMakerTradeFormClearRequested extends MarketMakerTradeFormEvent {
  const MarketMakerTradeFormClearRequested();
}

class MarketMakerTradeFormSwapCoinsRequested extends MarketMakerTradeFormEvent {
  const MarketMakerTradeFormSwapCoinsRequested();
}

class MarketMakerTradeFormEditOrderRequested extends MarketMakerTradeFormEvent {
  const MarketMakerTradeFormEditOrderRequested(
    this.tradePair, {
    required this.walletSession,
  });

  final TradePair tradePair;
  final MarketMakerBotWalletSession walletSession;

  @override
  List<Object> get props => [tradePair, walletSession];
}

class MarketMakerTradeFormAskOrderbookSelected
    extends MarketMakerTradeFormEvent {
  const MarketMakerTradeFormAskOrderbookSelected(this.order);

  final Order order;

  @override
  List<Object> get props => [order];
}

class MarketMakerConfirmationPreviewRequested
    extends MarketMakerTradeFormEvent {
  const MarketMakerConfirmationPreviewRequested({
    required this.walletSession,
    required this.draftRevision,
  });

  final MarketMakerBotWalletSession? walletSession;
  final int draftRevision;

  @override
  List<Object?> get props => [walletSession, draftRevision];
}

class MarketMakerConfirmationPreviewCancelRequested
    extends MarketMakerTradeFormEvent {
  const MarketMakerConfirmationPreviewCancelRequested();
}
