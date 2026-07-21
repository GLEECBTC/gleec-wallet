import 'dart:async';

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_tab_bar/dex_tab_bar_bloc.dart';
import 'package:web_dex/blocs/maker_form_bloc.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/advanced_trade_preparation.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/model/trade_preimage.dart';
import 'package:web_dex/shared/ui/ui_light_button.dart';
import 'package:web_dex/shared/utils/balances_formatter.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item_size.dart';
import 'package:web_dex/shared/widgets/segwit_icon.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';
import 'package:web_dex/views/dex/simple/form/exchange_info/exchange_rate.dart';
import 'package:web_dex/views/dex/simple/form/exchange_info/total_fees.dart';

class MakerOrderConfirmation extends StatefulWidget {
  const MakerOrderConfirmation({
    super.key,
    required this.onCreateOrder,
    required this.onCancel,
  });

  final VoidCallback onCancel;
  final VoidCallback onCreateOrder;

  @override
  State<MakerOrderConfirmation> createState() => _MakerOrderConfirmationState();
}

class _MakerOrderConfirmationState extends State<MakerOrderConfirmation> {
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<PreparedMakerOrder?>? _preparedSubscription;
  StreamSubscription<AdvancedTradeSubmissionStatus>? _statusSubscription;
  StreamSubscription<AdvancedTradeSubmissionFailure?>? _failureSubscription;
  MakerFormBloc? _makerFormBloc;
  PreparedMakerOrder? _preparedOrder;
  AdvancedTradeSubmissionStatus _submissionStatus =
      AdvancedTradeSubmissionStatus.idle;
  AdvancedTradeSubmissionFailure? _submissionFailure;
  String? _errorMessage;
  bool _inProgress = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bloc = RepositoryProvider.of<MakerFormBloc>(context);
    if (identical(bloc, _makerFormBloc)) return;
    _preparedSubscription?.cancel();
    _statusSubscription?.cancel();
    _failureSubscription?.cancel();
    _makerFormBloc = bloc;
    _preparedOrder = bloc.preparedOrder;
    _submissionStatus = bloc.submissionStatus;
    _submissionFailure = bloc.submissionFailure;
    _preparedSubscription = bloc.outPreparedOrder.listen((value) {
      if (mounted) setState(() => _preparedOrder = value);
    });
    _statusSubscription = bloc.outSubmissionStatus.listen((value) {
      if (mounted) setState(() => _submissionStatus = value);
    });
    _failureSubscription = bloc.outSubmissionFailure.listen((value) {
      if (mounted) setState(() => _submissionFailure = value);
    });
  }

  @override
  void dispose() {
    _preparedSubscription?.cancel();
    _statusSubscription?.cancel();
    _failureSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);

    return Container(
      padding: EdgeInsets.all(geometry.space24),
      constraints: BoxConstraints(
        maxWidth: Theme.of(context).calmCoreCompatibility.dexFormWidth,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border.all(color: colors.border),
        borderRadius: geometry.borderRadius24,
      ),
      child: _buildPreparedContent(coinsRepository),
    );
  }

  Widget _buildPreparedContent(CoinsRepo coinsRepository) {
    final prepared = _preparedOrder;
    if (prepared == null) return _buildUnavailableState();
    final TradePreimage preimage = prepared.preimage;
    final sellCoin = coinsRepository.getCoinFromId(prepared.baseAssetId);
    final buyCoin = coinsRepository.getCoinFromId(prepared.relAssetId);
    final sellAmount = prepared.volume;
    final buyAmount = sellAmount * prepared.price;
    if (sellCoin == null || buyCoin == null) {
      return Center(child: Text(LocaleKeys.dexErrorMessage.tr()));
    }

    return SingleChildScrollView(
      key: const Key('maker-order-conformation-scroll'),
      controller: _scrollController,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildTitle(),
          const SizedBox(height: 37),
          _buildReceive(buyCoin, buyAmount),
          _buildFiatReceive(
            sellCoin: sellCoin,
            buyCoin: buyCoin,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
          ),
          const SizedBox(height: 23),
          _buildSend(sellCoin, sellAmount),
          const SizedBox(height: 24),
          ExchangeRate(
            rate: prepared.price,
            base: prepared.base,
            rel: prepared.rel,
          ),
          const SizedBox(height: 10),
          TotalFees(preimage: preimage),
          const SizedBox(height: 24),
          _buildError(),
          _buildSubmissionNotice(),
          _buildButtons(sellCoin, buyCoin),
        ],
      ),
    );
  }

  Widget _buildBackButton() {
    return UiLightButton(
      onPressed:
          _inProgress ||
              _submissionStatus == AdvancedTradeSubmissionStatus.uncertain
          ? null
          : widget.onCancel,
      text: LocaleKeys.back.tr(),
    );
  }

  Widget _buildButtons(Coin sellCoin, Coin buyCoin) {
    return Row(
      children: [
        Flexible(child: _buildBackButton()),
        const SizedBox(width: 23),
        Flexible(child: _buildConfirmButton(sellCoin, buyCoin)),
      ],
    );
  }

  Widget _buildConfirmButton(Coin sellCoin, Coin buyCoin) {
    final tradingState = context.watch<TradingStatusBloc>().state;
    final bool tradingEnabled = tradingState.canTradeAssets([
      sellCoin.id,
      buyCoin.id,
    ]);

    return Opacity(
      opacity: _inProgress ? 0.8 : 1,
      child: UiPrimaryButton(
        key: const Key('make-order-confirm-button'),
        prefix: _inProgress
            ? Padding(
                padding: const EdgeInsets.only(right: 8),
                child: UiSpinner(
                  height: 10,
                  width: 10,
                  strokeWidth: 1,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              )
            : null,
        onPressed:
            _inProgress ||
                !tradingEnabled ||
                _preparedOrder == null ||
                _submissionStatus != AdvancedTradeSubmissionStatus.prepared
            ? null
            : _startSwap,
        text: tradingEnabled
            ? LocaleKeys.confirm.tr()
            : LocaleKeys.tradingDisabled.tr(),
      ),
    );
  }

  Widget _buildError() {
    final String? message = _errorMessage;
    if (message == null) return const SizedBox();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }

  Widget _buildUnavailableState() {
    if (_submissionStatus == AdvancedTradeSubmissionStatus.uncertain) {
      return Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sync_problem_rounded, size: 44),
            const SizedBox(height: 12),
            Text(
              'advancedTradeUncertainBody'.tr(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('maker-uncertain-view-activity'),
              onPressed: _viewAdvancedActivity,
              icon: const Icon(Icons.history_rounded),
              label: Text('advancedTradeRefreshActivity'.tr()),
            ),
          ],
        ),
      );
    }
    if (_submissionStatus == AdvancedTradeSubmissionStatus.failed ||
        _submissionFailure != null) {
      return Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _submissionFailureMessage(_submissionFailure),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _buildBackButton(),
          ],
        ),
      );
    }
    return const Center(child: UiSpinner());
  }

  Widget _buildSubmissionNotice() {
    final message = switch (_submissionStatus) {
      AdvancedTradeSubmissionStatus.submitting =>
        'advancedTradeSubmitting'.tr(),
      AdvancedTradeSubmissionStatus.accepted => 'advancedOrderAccepted'.tr(),
      AdvancedTradeSubmissionStatus.failed => _submissionFailureMessage(
        _submissionFailure,
      ),
      AdvancedTradeSubmissionStatus.uncertain =>
        'advancedTradeUncertainShort'.tr(),
      AdvancedTradeSubmissionStatus.idle ||
      AdvancedTradeSubmissionStatus.prepared => null,
    };
    if (message == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }

  String _submissionFailureMessage(AdvancedTradeSubmissionFailure? failure) {
    return switch (failure) {
      AdvancedTradeSubmissionFailure.walletChanged =>
        'advancedTradeWalletChanged'.tr(),
      AdvancedTradeSubmissionFailure.preparationExpired =>
        'advancedTradeExpired'.tr(),
      AdvancedTradeSubmissionFailure.tradingUnavailable =>
        'advancedTradeUnavailable'.tr(),
      AdvancedTradeSubmissionFailure.clockInvalid =>
        'advancedTradeClockInvalid'.tr(),
      AdvancedTradeSubmissionFailure.uncertain =>
        'advancedTradeUncertainBody'.tr(),
      AdvancedTradeSubmissionFailure.preparationInvalid ||
      AdvancedTradeSubmissionFailure.rejected ||
      AdvancedTradeSubmissionFailure.unknown ||
      null => 'advancedTradeInvalid'.tr(),
    };
  }

  Future<void> _viewAdvancedActivity() async {
    try {
      await RepositoryProvider.of<TradingEntitiesBloc>(context).fetch();
    } on Object {
      if (mounted) {
        setState(() => _errorMessage = 'advancedActivityRefreshFailed'.tr());
      }
    }
    if (!mounted) return;
    context.read<DexTabBarBloc>().add(const TabChanged(1));
  }

  Widget _buildFiatReceive({
    required Coin sellCoin,
    Rational? sellAmount,
    required Coin buyCoin,
    Rational? buyAmount,
  }) {
    if (sellAmount == null || buyAmount == null) return const SizedBox();

    Color? color = Theme.of(context).textTheme.bodyMedium?.color;
    double? percentage;

    final double sellAmtFiat = getFiatAmount(sellCoin, sellAmount);
    final double receiveAmtFiat = getFiatAmount(buyCoin, buyAmount);

    if (sellAmtFiat < receiveAmtFiat) {
      color = Theme.of(context).calmCoreCompatibility.increaseColor;
    } else if (sellAmtFiat > receiveAmtFiat) {
      color = Theme.of(context).calmCoreCompatibility.decreaseColor;
    }

    if (sellAmtFiat > 0 && receiveAmtFiat > 0) {
      percentage = (receiveAmtFiat - sellAmtFiat) * 100 / sellAmtFiat;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FiatAmount(coin: buyCoin, amount: buyAmount),
        if (percentage != null)
          Text(
            ' (${percentage > 0 ? '+' : ''}${formatAmt(percentage)}%)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w200,
            ),
          ),
      ],
    );
  }

  Widget _buildFiatSend(Coin coin, Rational? amount) {
    if (amount == null) return const SizedBox();
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 2, 0),
      child: FiatAmount(coin: coin, amount: amount),
    );
  }

  Widget _buildReceive(Coin coin, Rational? amount) {
    return Column(
      children: [
        SelectableText(
          LocaleKeys.swapConfirmationYouReceive.tr(),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).calmCoreCompatibility.dexSubTitleColor,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SelectableText(
              '${formatDexAmt(amount)} ',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            SelectableText(
              Coin.normalizeAbbr(coin.abbr),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).calmCoreCompatibility.balanceColor,
              ),
            ),
            if (coin.mode == CoinMode.segwit)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: SegwitIcon(height: 16),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSend(Coin coin, Rational? amount) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).calmCoreCompatibility.subCardBackgroundColor,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            LocaleKeys.swapConfirmationYouSending.tr(),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).calmCoreCompatibility.dexSubTitleColor,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.max,
            children: [
              CoinItem(coin: coin, size: CoinItemSize.large),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SelectableText(
                    formatDexAmt(amount),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 14.0,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  _buildFiatSend(coin, amount),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return SelectableText(
      LocaleKeys.swapConfirmationTitle.tr(),
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 16),
    );
  }

  Future<void> _startSwap() async {
    if (_preparedOrder == null ||
        _submissionStatus != AdvancedTradeSubmissionStatus.prepared ||
        _inProgress) {
      return;
    }
    setState(() {
      _errorMessage = null;
      _inProgress = true;
    });

    final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);
    final TextError? error = await makerFormBloc.makeOrder();

    if (!mounted) return;

    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );

    if (!mounted) return;
    setState(() => _inProgress = false);

    if (_submissionStatus == AdvancedTradeSubmissionStatus.uncertain) return;
    if (error != null ||
        _submissionStatus != AdvancedTradeSubmissionStatus.accepted) {
      setState(() {
        _errorMessage = _submissionFailureMessage(_submissionFailure);
      });
      return;
    }

    try {
      await tradingEntitiesBloc.fetch();
    } on Object {
      if (mounted) {
        setState(() => _errorMessage = 'advancedActivityRefreshFailed'.tr());
      }
    }
    if (!mounted) return;
    makerFormBloc.clear();
    widget.onCreateOrder();
  }
}
