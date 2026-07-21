import 'package:rational/rational.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders.dart';
import 'package:web_dex/model/available_balance_state.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/dex_form_error.dart';
import 'package:web_dex/model/advanced_trade_preparation.dart';
import 'package:web_dex/model/trade_preimage.dart';

class TakerState {
  TakerState({
    required this.step,
    required this.inProgress,
    this.sellCoin,
    this.selectedOrder,
    this.bestOrders,
    required this.showCoinSelector,
    required this.showOrderSelector,
    this.sellAmount,
    this.buyAmount,
    required List<DexFormError> errors,
    this.tradePreimage,
    this.maxSellAmount,
    this.minSellAmount,
    required this.autovalidate,
    this.swapUuid,
    required this.availableBalanceState,
    this.walletId,
    required this.formRevision,
    this.preparedTrade,
    required this.submissionStatus,
    this.submissionFailure,
  }) : errors = List<DexFormError>.unmodifiable(errors);

  factory TakerState.initial() {
    return TakerState(
      step: TakerStep.form,
      inProgress: false,
      sellCoin: null,
      selectedOrder: null,
      bestOrders: null,
      showCoinSelector: false,
      showOrderSelector: false,
      errors: [],
      tradePreimage: null,
      maxSellAmount: null,
      minSellAmount: null,
      autovalidate: false,
      swapUuid: null,
      availableBalanceState: AvailableBalanceState.initial,
      walletId: null,
      formRevision: 0,
      preparedTrade: null,
      submissionStatus: AdvancedTradeSubmissionStatus.idle,
      submissionFailure: null,
    );
  }

  final TakerStep step;
  final bool inProgress;
  final Coin? sellCoin;
  final BestOrder? selectedOrder;
  final BestOrders? bestOrders;
  final bool showCoinSelector;
  final bool showOrderSelector;
  final Rational? sellAmount;
  final Rational? buyAmount;
  final List<DexFormError> errors;
  final TradePreimage? tradePreimage;
  final Rational? maxSellAmount;
  final Rational? minSellAmount;
  final bool autovalidate;
  final String? swapUuid;
  final AvailableBalanceState availableBalanceState;

  /// Stable wallet identity that owns all async form state.
  final String? walletId;

  /// Monotonically increases whenever an execution-relevant input changes.
  final int formRevision;

  /// Exact immutable request reviewed on the confirmation screen.
  final PreparedTakerTrade? preparedTrade;
  final AdvancedTradeSubmissionStatus submissionStatus;
  final AdvancedTradeSubmissionFailure? submissionFailure;

  // Function arguments needed to handle nullable props
  // https://bloclibrary.dev/#/fluttertodostutorial
  // https://stackoverflow.com/questions/68009392/dart-custom-copywith-method-with-nullable-properties
  TakerState copyWith({
    TakerStep Function()? step,
    bool Function()? inProgress,
    Coin? Function()? sellCoin,
    BestOrder? Function()? selectedOrder,
    BestOrders? Function()? bestOrders,
    bool Function()? showCoinSelector,
    bool Function()? showOrderSelector,
    Rational? Function()? sellAmount,
    Rational? Function()? buyAmount,
    List<DexFormError> Function()? errors,
    TradePreimage? Function()? tradePreimage,
    Rational? Function()? maxSellAmount,
    Rational? Function()? minSellAmount,
    bool Function()? autovalidate,
    String? Function()? swapUuid,
    AvailableBalanceState Function()? availableBalanceState,
    String? Function()? walletId,
    int Function()? formRevision,
    PreparedTakerTrade? Function()? preparedTrade,
    AdvancedTradeSubmissionStatus Function()? submissionStatus,
    AdvancedTradeSubmissionFailure? Function()? submissionFailure,
  }) {
    return TakerState(
      step: step == null ? this.step : step(),
      inProgress: inProgress == null ? this.inProgress : inProgress(),
      sellCoin: sellCoin == null ? this.sellCoin : sellCoin(),
      selectedOrder: selectedOrder == null
          ? this.selectedOrder
          : selectedOrder(),
      bestOrders: bestOrders == null ? this.bestOrders : bestOrders(),
      showCoinSelector: showCoinSelector == null
          ? this.showCoinSelector
          : showCoinSelector(),
      showOrderSelector: showOrderSelector == null
          ? this.showOrderSelector
          : showOrderSelector(),
      sellAmount: sellAmount == null ? this.sellAmount : sellAmount(),
      buyAmount: buyAmount == null ? this.buyAmount : buyAmount(),
      errors: errors == null ? this.errors : errors(),
      tradePreimage: tradePreimage == null
          ? this.tradePreimage
          : tradePreimage(),
      maxSellAmount: maxSellAmount == null
          ? this.maxSellAmount
          : maxSellAmount(),
      minSellAmount: minSellAmount == null
          ? this.minSellAmount
          : minSellAmount(),
      autovalidate: autovalidate == null ? this.autovalidate : autovalidate(),
      swapUuid: swapUuid == null ? this.swapUuid : swapUuid(),
      availableBalanceState: availableBalanceState == null
          ? this.availableBalanceState
          : availableBalanceState(),
      walletId: walletId == null ? this.walletId : walletId(),
      formRevision: formRevision == null ? this.formRevision : formRevision(),
      preparedTrade: preparedTrade == null
          ? this.preparedTrade
          : preparedTrade(),
      submissionStatus: submissionStatus == null
          ? this.submissionStatus
          : submissionStatus(),
      submissionFailure: submissionFailure == null
          ? this.submissionFailure
          : submissionFailure(),
    );
  }
}

enum TakerStep { form, confirm }
