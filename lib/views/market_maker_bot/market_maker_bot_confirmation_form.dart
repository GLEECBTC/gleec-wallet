import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_bloc.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_trade_form/market_maker_trade_form_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/ui/ui_light_button.dart';
import 'package:web_dex/shared/utils/balances_formatter.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item_size.dart';
import 'package:web_dex/shared/widgets/segwit_icon.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';
import 'package:web_dex/views/dex/simple/form/exchange_info/exchange_rate.dart';
import 'package:web_dex/views/dex/simple/form/exchange_info/total_fees.dart';
import 'package:web_dex/views/market_maker_bot/important_note.dart';
import 'package:web_dex/views/market_maker_bot/market_maker_form_error_message_extensions.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/analytics/events/market_bot_events.dart';

class MarketMakerBotConfirmationForm extends StatefulWidget {
  const MarketMakerBotConfirmationForm({
    super.key,
    required this.onCreateOrder,
    required this.onCancel,
  });

  final VoidCallback onCancel;
  final VoidCallback onCreateOrder;

  @override
  State<MarketMakerBotConfirmationForm> createState() =>
      _MarketMakerBotConfirmationFormState();
}

class _MarketMakerBotConfirmationFormState
    extends State<MarketMakerBotConfirmationForm> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: isMobile
          ? const EdgeInsets.only(top: 18.0)
          : const EdgeInsets.only(top: 9.0),
      constraints: BoxConstraints(maxWidth: theme.custom.dexFormWidth),
      child: BlocBuilder<MarketMakerTradeFormBloc, MarketMakerTradeFormState>(
        builder: (context, state) {
          final walletSession = context
              .watch<MarketMakerBotBloc>()
              .captureWalletSession();
          final hasCurrentPreview = state.hasCurrentPreviewFor(walletSession);
          if (state.status == MarketMakerTradeFormStatus.loading) {
            return const UiSpinner();
          }

          if (state.buyCoin.value == null || state.sellCoin.value == null) {
            return const SizedBox();
          }

          final hasError =
              !hasCurrentPreview ||
              state.tradePreImageError != null ||
              state.status == MarketMakerTradeFormStatus.error;

          final VoidCallback? onCreateOrderCallback = hasError
              ? null
              : () {
                  final sellAmt = state.sellAmount.valueAsRational.toDouble();
                  final price =
                      state.priceFromUsd ?? state.priceFromUsdWithMargin ?? 0.0;
                  final baseCapital = price > 0 ? sellAmt * price : sellAmt;
                  context.read<AnalyticsBloc>().logEvent(
                    MarketbotSetupCompleteEventData(
                      strategyType: 'simple',
                      baseCapital: baseCapital,
                    ),
                  );
                  widget.onCreateOrder();
                };

          return SingleChildScrollView(
            key: const Key('maker-order-conformation-scroll'),
            controller: ScrollController(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SelectableText(
                  LocaleKeys.mmBotFirstTradePreview.tr(),
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 37),
                ImportantNote(
                  text: LocaleKeys.mmBotFirstOrderVolume.tr(
                    args: [state.sellCoin.value?.abbr ?? ''],
                  ),
                ),
                const SizedBox(height: 10),
                ImportantNote(text: 'marketMakerRestartImpact'.tr()),
                const SizedBox(height: 10),
                SwapReceiveAmount(
                  context: context,
                  coin: state.buyCoin.value!,
                  amount: state.buyAmount.valueAsRational,
                ),
                SwapFiatReceivedAmount(
                  context: context,
                  sellCoin: state.sellCoin.value!,
                  sellAmount: state.sellAmount.valueAsRational,
                  buyCoin: state.buyCoin.value!,
                  buyAmount: state.buyAmount.valueAsRational,
                ),
                const SizedBox(height: 23),
                SwapSendAmount(
                  context: context,
                  coin: state.sellCoin.value!,
                  amount: state.sellAmount.valueAsRational,
                ),
                const SizedBox(height: 24),
                ExchangeRate(
                  base: state.sellCoin.value?.abbr,
                  rel: state.buyCoin.value?.abbr,
                  rate: state.priceFromUsdWithMarginRational,
                ),
                const SizedBox(height: 10),
                TotalFees(
                  preimage: hasCurrentPreview ? state.tradePreImage : null,
                ),
                const SizedBox(height: 24),
                SwapErrorMessage(
                  errorMessage:
                      state.rawErrorMessage ??
                      state.tradePreImageError?.text(
                        state.sellCoin.value,
                        state.buyCoin.value,
                      ),
                  context: context,
                ),
                Flexible(
                  child: SwapActionButtons(
                    onCancel: widget.onCancel,
                    onCreateOrder: onCreateOrderCallback,
                    sellCoin: state.sellCoin.value,
                    buyCoin: state.buyCoin.value,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class SwapActionButtons extends StatelessWidget {
  const SwapActionButtons({
    super.key,
    required this.onCancel,
    required this.onCreateOrder,
    required this.sellCoin,
    required this.buyCoin,
  });

  final VoidCallback onCancel;
  final VoidCallback? onCreateOrder;
  final Coin? sellCoin;
  final Coin? buyCoin;

  @override
  Widget build(BuildContext context) {
    final tradingStatusBloc = context.watch<TradingStatusBloc>();

    final bool tradingEnabled = tradingStatusBloc.state.canTradeAssets([
      sellCoin?.id,
      buyCoin?.id,
    ]);

    return Row(
      children: [
        Flexible(
          child: UiLightButton(onPressed: onCancel, text: LocaleKeys.back.tr()),
        ),
        const SizedBox(width: 23),
        Flexible(
          child: UiPrimaryButton(
            key: const Key('market-maker-bot-order-confirm-button'),
            onPressed: !tradingEnabled ? null : onCreateOrder,
            text: tradingEnabled
                ? LocaleKeys.confirm.tr()
                : LocaleKeys.tradingDisabled.tr(),
          ),
        ),
      ],
    );
  }
}

class SwapErrorMessage extends StatelessWidget {
  const SwapErrorMessage({
    super.key,
    required String? errorMessage,
    required this.context,
  }) : _errorMessage = errorMessage;

  final String? _errorMessage;
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
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
}

class SwapSendAmount extends StatelessWidget {
  const SwapSendAmount({
    super.key,
    required this.context,
    required this.coin,
    required this.amount,
  });

  final BuildContext context;
  final Coin coin;
  final Rational? amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.custom.subCardBackgroundColor,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            LocaleKeys.swapConfirmationYouSending.tr(),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: theme.custom.dexSubTitleColor,
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
                  SwapFiatSendAmount(coin: coin, amount: amount),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SwapFiatSendAmount extends StatelessWidget {
  const SwapFiatSendAmount({
    super.key,
    required this.coin,
    required this.amount,
  });

  final Coin coin;
  final Rational? amount;

  @override
  Widget build(BuildContext context) {
    if (amount == null) return const SizedBox();
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 2, 0),
      child: FiatAmount(coin: coin, amount: amount ?? Rational.zero),
    );
  }
}

class SwapFiatReceivedAmount extends StatelessWidget {
  const SwapFiatReceivedAmount({
    super.key,
    required this.context,
    required this.sellCoin,
    required this.sellAmount,
    required this.buyCoin,
    required this.buyAmount,
  });

  final BuildContext context;
  final Coin sellCoin;
  final Rational? sellAmount;
  final Coin buyCoin;
  final Rational? buyAmount;

  @override
  Widget build(BuildContext context) {
    if (sellAmount == null || buyAmount == null) return const SizedBox();

    Color? color = Theme.of(context).textTheme.bodyMedium?.color;
    double? percentage;

    final double sellAmtFiat = getFiatAmount(
      sellCoin,
      sellAmount ?? Rational.zero,
    );
    final double receiveAmtFiat = getFiatAmount(
      buyCoin,
      buyAmount ?? Rational.zero,
    );

    if (sellAmtFiat < receiveAmtFiat) {
      color = theme.custom.increaseColor;
    } else if (sellAmtFiat > receiveAmtFiat) {
      color = theme.custom.decreaseColor;
    }

    if (sellAmtFiat > 0 && receiveAmtFiat > 0) {
      percentage = (receiveAmtFiat - sellAmtFiat) * 100 / sellAmtFiat;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FiatAmount(coin: buyCoin, amount: buyAmount ?? Rational.zero),
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
}

class SwapReceiveAmount extends StatelessWidget {
  const SwapReceiveAmount({
    super.key,
    required this.context,
    required this.coin,
    required this.amount,
  });

  final BuildContext context;
  final Coin coin;
  final Rational? amount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SelectableText(
          LocaleKeys.swapConfirmationYouReceive.tr(),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: theme.custom.dexSubTitleColor),
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
                color: theme.custom.balanceColor,
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
}
