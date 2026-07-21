import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_tab_bar/dex_tab_bar_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/bloc/taker_form/taker_state.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/dex_form_error.dart';
import 'package:web_dex/model/advanced_trade_preparation.dart';
import 'package:web_dex/model/trade_preimage.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/router/state/dex_state.dart';
import 'package:web_dex/shared/ui/ui_light_button.dart';
import 'package:web_dex/shared/utils/balances_formatter.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item_size.dart';
import 'package:web_dex/shared/widgets/segwit_icon.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';
import 'package:web_dex/views/dex/simple/form/exchange_info/exchange_rate.dart';
import 'package:web_dex/views/dex/simple/form/exchange_info/total_fees.dart';

class TakerOrderConfirmation extends StatefulWidget {
  const TakerOrderConfirmation({super.key});

  @override
  State<TakerOrderConfirmation> createState() => _TakerOrderConfirmationState();
}

class _TakerOrderConfirmationState extends State<TakerOrderConfirmation> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coinsBloc = RepositoryProvider.of<CoinsRepo>(context);
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
      child: BlocConsumer<TakerBloc, TakerState>(
        listenWhen: (previous, current) =>
            previous.swapUuid != current.swapUuid && current.swapUuid != null,
        listener: _onSwapStarted,
        buildWhen: (prev, current) {
          return prev.preparedTrade != current.preparedTrade ||
              prev.submissionStatus != current.submissionStatus ||
              prev.submissionFailure != current.submissionFailure ||
              prev.errors != current.errors;
        },
        builder: (context, state) {
          final prepared = state.preparedTrade;
          if (prepared == null) {
            return _buildUnavailableState(state);
          }
          final TradePreimage preimage = prepared.preimage;

          final Coin? sellCoin = coinsBloc.getCoinFromId(prepared.baseAssetId);
          final Coin? buyCoin = coinsBloc.getCoinFromId(prepared.relAssetId);
          final Rational sellAmount = prepared.volume;
          final Rational buyAmount = sellAmount * prepared.price;

          if (sellCoin == null || buyCoin == null) {
            return Center(child: Text(LocaleKeys.dexErrorMessage.tr()));
          }
          return DexScrollbar(
            scrollController: _scrollController,
            child: SingleChildScrollView(
              key: const Key('taker-order-confirmation-scroll'),
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
                  _buildSubmissionNotice(state),
                  _buildButtons(sellCoin, buyCoin, state),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBackButton() {
    return BlocSelector<TakerBloc, TakerState, bool>(
      selector: (state) => state.inProgress,
      builder: (context, inProgress) {
        return UiLightButton(
          onPressed: inProgress
              ? null
              : () => context.read<TakerBloc>().add(TakerBackButtonClick()),
          text: LocaleKeys.back.tr(),
        );
      },
    );
  }

  Widget _buildUnavailableState(TakerState state) {
    if (state.submissionStatus == AdvancedTradeSubmissionStatus.uncertain) {
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
              key: const Key('taker-uncertain-view-activity'),
              onPressed: _viewAdvancedActivity,
              icon: const Icon(Icons.history_rounded),
              label: Text('advancedTradeRefreshActivity'.tr()),
            ),
          ],
        ),
      );
    }
    if (state.submissionStatus == AdvancedTradeSubmissionStatus.failed ||
        state.submissionFailure != null) {
      return Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _submissionFailureMessage(state.submissionFailure),
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

  Widget _buildSubmissionNotice(TakerState state) {
    final message = switch (state.submissionStatus) {
      AdvancedTradeSubmissionStatus.submitting =>
        'advancedTradeSubmitting'.tr(),
      AdvancedTradeSubmissionStatus.accepted => 'advancedSwapAccepted'.tr(),
      AdvancedTradeSubmissionStatus.failed => _submissionFailureMessage(
        state.submissionFailure,
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
      // Navigation remains available when the refresh itself fails.
    }
    if (!mounted || !context.mounted) return;
    context.read<DexTabBarBloc>().add(const TabChanged(1));
  }

  Widget _buildButtons(Coin sellCoin, Coin buyCoin, TakerState state) {
    return Row(
      children: [
        Flexible(child: _buildBackButton()),
        const SizedBox(width: 23),
        Flexible(child: _buildConfirmButton(sellCoin, buyCoin, state)),
      ],
    );
  }

  Widget _buildConfirmButton(Coin sellCoin, Coin buyCoin, TakerState state) {
    final tradingStatusState = context.watch<TradingStatusBloc>().state;
    final bool tradingEnabled = tradingStatusState.canTradeAssets([
      sellCoin.id,
      buyCoin.id,
    ]);

    return BlocBuilder<TakerBloc, TakerState>(
      buildWhen: (previous, current) =>
          previous.inProgress != current.inProgress ||
          previous.preparedTrade != current.preparedTrade ||
          previous.submissionStatus != current.submissionStatus,
      builder: (context, current) {
        final inProgress = current.inProgress;
        final canSubmit =
            current.preparedTrade == state.preparedTrade &&
            current.preparedTrade != null &&
            current.submissionStatus == AdvancedTradeSubmissionStatus.prepared;
        return Opacity(
          opacity: inProgress ? 0.8 : 1,
          child: UiPrimaryButton(
            key: const Key('take-order-confirm-button'),
            prefix: inProgress
                ? Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: UiSpinner(
                      width: 10,
                      height: 10,
                      strokeWidth: 1,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  )
                : null,
            onPressed: inProgress || !tradingEnabled || !canSubmit
                ? null
                : () => _startSwap(context),
            text: tradingEnabled
                ? LocaleKeys.confirm.tr()
                : LocaleKeys.tradingDisabled.tr(),
          ),
        );
      },
    );
  }

  Widget _buildError() {
    return BlocSelector<TakerBloc, TakerState, List<DexFormError>>(
      selector: (state) => state.errors,
      builder: (context, errors) {
        if (errors.isEmpty) return const SizedBox.shrink();
        final String message = errors.first.error;

        return Container(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        );
      },
    );
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

  Future<void> _startSwap(BuildContext context) async {
    final takerBloc = context.read<TakerBloc>();
    if (takerBloc.state.preparedTrade == null ||
        takerBloc.state.submissionStatus !=
            AdvancedTradeSubmissionStatus.prepared) {
      takerBloc.add(
        TakerAddError(
          DexFormError(error: LocaleKeys.dexUnableToStartSwap.tr()),
        ),
      );
      takerBloc.add(TakerSetInProgress(false));
      return;
    }

    context.read<TakerBloc>().add(TakerStartSwap());
  }

  Future<void> _onSwapStarted(BuildContext context, TakerState state) async {
    final String? uuid = state.swapUuid;
    if (uuid == null) return;

    final routed = routingState.dexState.setDetailsAction(
      uuid,
      kind: DexTradingEntityKind.swap,
    );
    if (!routed) {
      context.read<TakerBloc>().add(
        TakerAddError(DexFormError(error: 'advancedTradeInvalid'.tr())),
      );
      return;
    }
    context.read<TakerBloc>().add(TakerClear());

    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    // Give MM2/KDF a short moment to register the swap before first fetch
    await Future<dynamic>.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    try {
      await tradingEntitiesBloc.fetch();
    } on Object {
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('advancedActivityRefreshFailed'.tr())),
      );
    }
  }
}
