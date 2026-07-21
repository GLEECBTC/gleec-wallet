part of 'market_maker_trade_form_bloc.dart';

enum MarketMakerTradeFormError {
  insufficientBalanceBase,
  insufficientBalanceRel,
  insufficientBalanceRelParent,
  insufficientTradeAmount,
  none,
}

enum MarketMakerTradeFormStatus { initial, loading, success, error }

// Usually this would be a dedicated tab contoller/ui flow bloc, but because
// there is only two stages (initial and confirmationRequired), and for the
// sake of simplicity, we are using the form state to manage the form stages.
enum MarketMakerTradeFormStage { initial, confirmationRequired }

/// The state of the market maker trade form. The state is a formz mixin
/// which allows the form to be validated and checked for errors.
class MarketMakerTradeFormState extends Equatable with FormzMixin {
  const MarketMakerTradeFormState({
    required this.sellCoin,
    required this.buyCoin,
    required this.minimumTradeVolume,
    required this.maximumTradeVolume,
    required this.sellAmount,
    required this.buyAmount,
    required this.tradeMargin,
    required this.updateInterval,
    required this.status,
    required this.stage,
    required this.draftRevision,
    this.tradePreImageError,
    this.tradePreImage,
    this.maxMakerVolume,
    this.minTradingVolume,
    this.rawErrorMessage,
    this.isLoadingMaxMakerVolume = false,
    this.walletSession,
    this.originalConfig,
    this.previewRevision,
    this.previewWalletSession,
  });

  MarketMakerTradeFormState.initial({this.draftRevision = 0})
    : sellCoin = const CoinSelectInput.pure(),
      buyCoin = const CoinSelectInput.pure(),
      minimumTradeVolume = const TradeVolumeInput.pure(0.1),
      maximumTradeVolume = const TradeVolumeInput.pure(0.9),
      sellAmount = const CoinTradeAmountInput.pure(),
      buyAmount = const CoinTradeAmountInput.pure(),
      tradeMargin = const TradeMarginInput.pure(),
      updateInterval = const UpdateIntervalInput.pure(),
      status = MarketMakerTradeFormStatus.initial,
      stage = MarketMakerTradeFormStage.initial,
      tradePreImageError = null,
      tradePreImage = null,
      maxMakerVolume = null,
      minTradingVolume = null,
      rawErrorMessage = null,
      isLoadingMaxMakerVolume = false,
      walletSession = null,
      originalConfig = null,
      previewRevision = null,
      previewWalletSession = null;

  /// The coin being sold in the trade pair (base coin).
  final CoinSelectInput sellCoin;

  /// The coin being bought in the trade pair (rel coin).
  final CoinSelectInput buyCoin;

  /// The minimum volume to use per trade. E.g. The minimum trade volume in USD.
  final TradeVolumeInput minimumTradeVolume;

  /// The maximum volume to use per trade.
  /// E.g. The maximum trade volume in percentage.
  final TradeVolumeInput maximumTradeVolume;

  /// The amount of the base coin being sold.
  final CoinTradeAmountInput sellAmount;

  /// The amount of the rel coin being bought.
  final CoinTradeAmountInput buyAmount;

  /// The trade margin percentage over the usd market price (cex rate).
  final TradeMarginInput tradeMargin;

  /// The interval at which the market maker bot should update the trade pair.
  /// The interval is in seconds.
  final UpdateIntervalInput updateInterval;

  /// Whether the form is in the initial, in progress, success or error state.
  final MarketMakerTradeFormStatus status;

  /// The error state of the form.
  final MarketMakerTradeFormError? tradePreImageError;

  /// The current stage of the form (confirmation or initial).
  final MarketMakerTradeFormStage stage;

  /// Monotonically increases whenever an execution-relevant draft value
  /// changes. Async work may only publish results for the revision it read.
  final int draftRevision;

  /// The preimage of the trade pair, used to calculate the trade pair fees.
  final TradePreimage? tradePreImage;

  /// The maximum maker volume available for swaps for the sell coin.
  /// This value is fetched from the DEX API and cached in the state.
  final Rational? maxMakerVolume;

  /// The minimum trading volume required by the base coin (sell coin).
  /// Retrieved from the DEX API `min_trading_vol` for clearer validation
  /// and error messaging.
  final Rational? minTradingVolume;

  /// Sanitized user-facing message for a generic/transport failure that
  /// persists after retries. Backend error payloads must never be stored here.
  final String? rawErrorMessage;

  /// Indicates whether the max maker volume is currently being fetched.
  final bool isLoadingMaxMakerVolume;

  /// Wallet session that owns this edit or confirmation draft.
  ///
  /// Carrying this through confirmation prevents a draft prepared from a
  /// previous wallet snapshot from mutating whichever wallet is current later.
  final MarketMakerBotWalletSession? walletSession;

  /// Exact configuration snapshot that opened edit mode.
  ///
  /// New strategies leave this null. Existing strategies carry it through the
  /// confirmation flow so the lifecycle BLoC can reject a stale edit instead
  /// of re-adding a strategy removed by a newer snapshot.
  final TradeCoinPairConfig? originalConfig;

  /// Draft revision for which [tradePreImage] was successfully fetched.
  final int? previewRevision;

  /// Wallet session for which [tradePreImage] was successfully fetched.
  final MarketMakerBotWalletSession? previewWalletSession;

  /// Whether the confirmation currently represents this exact draft and
  /// wallet session.
  bool get hasCurrentPreview => hasCurrentPreviewFor(walletSession);

  bool hasCurrentPreviewFor(MarketMakerBotWalletSession? session) {
    return session != null &&
        stage == MarketMakerTradeFormStage.confirmationRequired &&
        status == MarketMakerTradeFormStatus.success &&
        isValid &&
        tradePreImageError == null &&
        rawErrorMessage == null &&
        tradePreImage != null &&
        previewRevision == draftRevision &&
        previewWalletSession == session &&
        walletSession == session;
  }

  /// The price of the trade pair derived from the USD price of the coins.
  /// Price = baseCoinUsdPrice / relCoinUsdPrice.
  double? get priceFromUsd {
    final baseUsdPrice = sellCoin.value?.usdPrice?.price?.toDouble();
    final relUsdPrice = buyCoin.value?.usdPrice?.price?.toDouble();
    if (baseUsdPrice == null ||
        relUsdPrice == null ||
        !baseUsdPrice.isFinite ||
        !relUsdPrice.isFinite ||
        baseUsdPrice <= 0 ||
        relUsdPrice <= 0) {
      return null;
    }

    final price = baseUsdPrice / relUsdPrice;
    return price.isFinite && price > 0 ? price : null;
  }

  /// The price of the trade pair derived from the USD price of the coins
  /// with the trade margin applied. The trade margin is a percentage over
  /// the usd market price (cex rate).
  double? get priceFromUsdWithMargin {
    final price = priceFromUsd;
    final spreadPercentage = double.tryParse(tradeMargin.value);
    if (price == null ||
        spreadPercentage == null ||
        !spreadPercentage.isFinite) {
      return null;
    }

    final adjustedPrice = price * (1 + (spreadPercentage / 100));
    return adjustedPrice.isFinite && adjustedPrice > 0 ? adjustedPrice : null;
  }

  /// The price of the trade pair derived from the USD price of the coins
  /// with the trade margin applied. The trade margin is a percentage over
  /// the usd market price (cex rate).
  Rational? get priceFromUsdWithMarginRational {
    final price = priceFromUsdWithMargin;
    return price != null ? Rational.parse(price.toString()) : null;
  }

  /// The price of the trade pair derived from the amount of the coins.
  /// Price = buyAmount / sellAmount.
  double get priceFromAmount {
    final sellAmount = double.tryParse(this.sellAmount.value) ?? 0;
    final buyAmount = double.tryParse(this.buyAmount.value) ?? 0;
    if (!sellAmount.isFinite ||
        !buyAmount.isFinite ||
        sellAmount <= 0 ||
        buyAmount < 0) {
      return 0;
    }
    final price = buyAmount / sellAmount;
    return price.isFinite && price >= 0 ? price : 0;
  }

  /// The margin percentage derived from the amount of the coins.
  /// Margin = (priceFromAmount / priceFromUsd - 1) * 100.
  double get marginFromAmounts {
    double newMargin = tradeMargin.valueAsDouble;
    if (sellAmount.value.isEmpty) {
      return newMargin;
    }

    final currentPrice = priceFromUsd;
    if (currentPrice == null || currentPrice == 0) {
      return newMargin;
    }

    final amountPrice = priceFromAmount;
    if (currentPrice == amountPrice) {
      return newMargin;
    }

    final calculatedMargin = (amountPrice / currentPrice - 1) * 100;
    return calculatedMargin.isFinite ? calculatedMargin : newMargin;
  }

  MarketMakerTradeFormState copyWith({
    CoinSelectInput? sellCoin,
    CoinSelectInput? buyCoin,
    TradeVolumeInput? minimumTradeVolume,
    TradeVolumeInput? maximumTradeVolume,
    CoinTradeAmountInput? sellAmount,
    CoinTradeAmountInput? buyAmount,
    TradeMarginInput? tradeMargin,
    UpdateIntervalInput? updateInterval,
    MarketMakerTradeFormStatus? status,
    MarketMakerTradeFormError? Function()? preImageError,
    MarketMakerTradeFormStage? stage,
    int? draftRevision,
    TradePreimage? Function()? tradePreImage,
    Rational? Function()? maxMakerVolume,
    Rational? Function()? minTradingVolume,
    String? Function()? rawErrorMessage,
    bool? isLoadingMaxMakerVolume,
    MarketMakerBotWalletSession? Function()? walletSession,
    TradeCoinPairConfig? Function()? originalConfig,
    int? Function()? previewRevision,
    MarketMakerBotWalletSession? Function()? previewWalletSession,
  }) {
    return MarketMakerTradeFormState(
      sellCoin: sellCoin ?? this.sellCoin,
      buyCoin: buyCoin ?? this.buyCoin,
      minimumTradeVolume: minimumTradeVolume ?? this.minimumTradeVolume,
      maximumTradeVolume: maximumTradeVolume ?? this.maximumTradeVolume,
      sellAmount: sellAmount ?? this.sellAmount,
      buyAmount: buyAmount ?? this.buyAmount,
      tradeMargin: tradeMargin ?? this.tradeMargin,
      updateInterval: updateInterval ?? this.updateInterval,
      status: status ?? this.status,
      tradePreImageError: preImageError == null
          ? tradePreImageError
          : preImageError(),
      stage: stage ?? this.stage,
      draftRevision: draftRevision ?? this.draftRevision,
      tradePreImage: tradePreImage == null
          ? this.tradePreImage
          : tradePreImage(),
      maxMakerVolume: maxMakerVolume == null
          ? this.maxMakerVolume
          : maxMakerVolume(),
      minTradingVolume: minTradingVolume == null
          ? this.minTradingVolume
          : minTradingVolume(),
      rawErrorMessage: rawErrorMessage == null
          ? this.rawErrorMessage
          : rawErrorMessage(),
      isLoadingMaxMakerVolume:
          isLoadingMaxMakerVolume ?? this.isLoadingMaxMakerVolume,
      walletSession: walletSession == null
          ? this.walletSession
          : walletSession(),
      originalConfig: originalConfig == null
          ? this.originalConfig
          : originalConfig(),
      previewRevision: previewRevision == null
          ? this.previewRevision
          : previewRevision(),
      previewWalletSession: previewWalletSession == null
          ? this.previewWalletSession
          : previewWalletSession(),
    );
  }

  /// Converts the form state to a [TradeCoinPairConfig] object to be used
  /// in the market maker bot parameters.
  TradeCoinPairConfig toTradePairConfig() {
    final baseCoinId = sellCoin.value?.abbr;
    final relCoinId = buyCoin.value?.abbr;
    final spreadPercentage = double.tryParse(tradeMargin.value);
    final interval = updateInterval.isValid ? updateInterval.interval : null;
    if (!isValid ||
        baseCoinId == null ||
        relCoinId == null ||
        spreadPercentage == null ||
        !spreadPercentage.isFinite ||
        interval == null ||
        minimumTradeVolume.value > maximumTradeVolume.value) {
      throw const FormatException('Invalid market maker configuration');
    }
    final spread = 1 + (spreadPercentage / 100);
    if (!spread.isFinite) {
      throw const FormatException('Invalid market maker configuration');
    }

    return TradeCoinPairConfig(
      name: TradeCoinPairConfig.getSimpleName(baseCoinId, relCoinId),
      baseCoinId: baseCoinId,
      relCoinId: relCoinId,
      spread: spread.toString(),
      priceElapsedValidity: interval.seconds,
      maxVolume: TradeVolume.percentage(maximumTradeVolume.value),
      minVolume: TradeVolume.percentage(minimumTradeVolume.value),
    );
  }

  @override
  List<FormzInput<dynamic, dynamic>> get inputs => [
    sellCoin,
    buyCoin,
    minimumTradeVolume,
    maximumTradeVolume,
    tradeMargin,
    updateInterval,
  ];

  @override
  bool get isValid {
    return super.isValid &&
        minimumTradeVolume.value <= maximumTradeVolume.value &&
        tradePreImageError == null &&
        status != MarketMakerTradeFormStatus.error;
  }

  @override
  List<Object?> get props => [
    sellCoin,
    buyCoin,
    minimumTradeVolume,
    maximumTradeVolume,
    sellAmount,
    buyAmount,
    tradeMargin,
    updateInterval,
    tradePreImageError,
    stage,
    draftRevision,
    status,
    tradePreImage,
    maxMakerVolume,
    minTradingVolume,
    rawErrorMessage,
    isLoadingMaxMakerVolume,
    walletSession,
    originalConfig,
    previewRevision,
    previewWalletSession,
  ];
}
