import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/bloc/taker_form/taker_state.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/analytics/events/transaction_events.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/dex_form_error.dart';
import 'package:web_dex/model/trade_preimage.dart';
import 'package:web_dex/shared/utils/extensions/kdf_user_extensions.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/ui/ui_light_button.dart';
import 'package:web_dex/shared/utils/balances_formatter.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item_size.dart';
import 'package:web_dex/shared/widgets/segwit_icon.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';
import 'package:web_dex/views/dex/simple/form/taker/taker_form_exchange_rate.dart';
import 'package:web_dex/views/dex/simple/form/taker/taker_form_total_fees.dart';

class TakerOrderConfirmation extends StatefulWidget {
  const TakerOrderConfirmation({super.key});

  @override
  State<TakerOrderConfirmation> createState() => _TakerOrderConfirmationState();
}

class _TakerOrderConfirmationState extends State<TakerOrderConfirmation> {
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
        listenWhen: (prev, current) => current.swapUuid != null,
        listener: _onSwapStarted,
        buildWhen: (prev, current) {
          return prev.tradePreimage != current.tradePreimage;
        },
        builder: (context, state) {
          final TradePreimage? preimage = state.tradePreimage;
          if (preimage == null) return const UiSpinner();

          final Coin? sellCoin = coinsBloc.getCoin(preimage.request.base);
          final Coin? buyCoin = coinsBloc.getCoin(preimage.request.rel);
          final Rational? sellAmount = preimage.request.volume;
          final Rational buyAmount =
              (sellAmount ?? Rational.zero) * preimage.request.price;

          if (sellCoin == null || buyCoin == null) {
            return Center(child: Text(LocaleKeys.dexErrorMessage.tr()));
          }
          final scrollController = ScrollController();
          return DexScrollbar(
            scrollController: scrollController,
            child: SingleChildScrollView(
              key: const Key('taker-order-confirmation-scroll'),
              controller: scrollController,
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
                  const TakerFormExchangeRate(),
                  const SizedBox(height: 10),
                  const TakerFormTotalFees(),
                  const SizedBox(height: 24),
                  _buildError(),
                  Flexible(child: _buildButtons(sellCoin, buyCoin)),
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
    final tradingStatusState = context.watch<TradingStatusBloc>().state;
    final bool tradingEnabled = tradingStatusState.canTradeAssets([
      sellCoin.id,
      buyCoin.id,
    ]);

    return BlocSelector<TakerBloc, TakerState, bool>(
      selector: (state) => state.inProgress,
      builder: (context, inProgress) {
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
            onPressed: inProgress || !tradingEnabled
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
    final authBloc = context.read<AuthBloc>();
    final walletType = authBloc.state.currentUser?.type ?? '';
    final takerBloc = context.read<TakerBloc>();
    final coinsRepo = RepositoryProvider.of<CoinsRepo>(context);
    final sellCoinObj = takerBloc.state.sellCoin;
    final selectedOrder = takerBloc.state.selectedOrder;
    final sellAmount = takerBloc.state.sellAmount;

    if (sellCoinObj == null || selectedOrder == null || sellAmount == null) {
      takerBloc.add(
        TakerAddError(
          DexFormError(error: LocaleKeys.dexUnableToStartSwap.tr()),
        ),
      );
      takerBloc.add(TakerSetInProgress(false));
      return;
    }

    final buyCoinObj = coinsRepo.getCoin(selectedOrder.coin);
    final sellCoin = sellCoinObj.abbr;
    final buyCoin = buyCoinObj?.abbr ?? selectedOrder.coin;
    context.read<AnalyticsBloc>().logEvent(
      SwapInitiatedEventData(
        asset: sellCoin,
        secondaryAsset: buyCoin,
        network: sellCoinObj.protocolType,
        secondaryNetwork: buyCoinObj?.protocolType ?? 'unknown',
        hdType: walletType,
      ),
    );
    context.read<TakerBloc>().add(TakerStartSwap());
  }

  Future<void> _onSwapStarted(BuildContext context, TakerState state) async {
    final String? uuid = state.swapUuid;
    if (uuid == null) return;

    context.read<TakerBloc>().add(TakerClear());
    routingState.dexState.setDetailsAction(uuid);

    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    // Give MM2/KDF a short moment to register the swap before first fetch
    await Future<dynamic>.delayed(const Duration(seconds: 1));
    await tradingEntitiesBloc.fetch();
  }
}
