import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/analytics/events/market_bot_events.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_trade_form/market_maker_trade_form_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/ui/ui_light_button.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/connect_wallet/connect_wallet_wrapper.dart';
import 'package:web_dex/views/dex/common/form_plate.dart';
import 'package:web_dex/views/dex/simple/form/common/dex_flip_button_overlapper.dart';
import 'package:web_dex/views/dex/simple/form/common/dex_info_container.dart';
import 'package:web_dex/views/dex/simple/form/exchange_info/exchange_rate.dart';
import 'package:web_dex/views/market_maker_bot/add_market_maker_bot_trade_button.dart';
import 'package:web_dex/views/market_maker_bot/buy_coin_select_dropdown.dart';
import 'package:web_dex/views/market_maker_bot/important_note.dart';
import 'package:web_dex/views/market_maker_bot/market_maker_form_error_message_extensions.dart';
import 'package:web_dex/views/market_maker_bot/sell_coin_select_dropdown.dart';
import 'package:web_dex/views/market_maker_bot/trade_bot_update_interval.dart';
import 'package:web_dex/views/market_maker_bot/update_interval_dropdown.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';

class MarketMakerBotFormContent extends StatefulWidget {
  const MarketMakerBotFormContent({required this.coins, super.key});

  final List<Coin> coins;

  @override
  State<MarketMakerBotFormContent> createState() =>
      _MarketMakerBotFormContentState();
}

class _MarketMakerBotFormContentState extends State<MarketMakerBotFormContent> {
  @override
  void initState() {
    _setSellCoinToDefaultCoin();
    super.initState();
  }

  @override
  void didUpdateWidget(MarketMakerBotFormContent oldWidget) {
    if (oldWidget.coins != widget.coins) {
      final formBloc = context.read<MarketMakerTradeFormBloc>();
      if (formBloc.state.sellCoin.value == null) {
        _setSellCoinToDefaultCoin();
      }
      // Removed re-dispatch of MarketMakerTradeFormSellCoinChanged event
      // as it causes flickering when coins list updates during coin selection.
      // The event is already dispatched by _onSelectSellCoin when user
      // selects a coin, so re-dispatching here creates a race condition.
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    const keyPrefix = 'market-maker-bot-form';

    return BlocBuilder<MarketMakerTradeFormBloc, MarketMakerTradeFormState>(
      builder: (context, state) {
        return FormPlate(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 20),
            child: Form(
              child: Column(
                children: [
                  DexFlipButtonOverlapper(
                    offsetTop: 208.0,
                    onTap: _swapBuyAndSellCoins,
                    topWidget: SellCoinSelectDropdown(
                      key: const Key('$keyPrefix-sell-select'),
                      sellCoin: state.sellCoin,
                      sellAmount: state.sellAmount,
                      coins: _sellableCoins(widget.coins),
                      minimumTradeVolume: state.minimumTradeVolume,
                      maximumTradeVolume: state.maximumTradeVolume,
                      onItemSelected: _onSelectSellCoin,
                      onTradeVolumeChanged: _onVolumeRangeChanged,
                      showSellAmountSpinner: state.isLoadingMaxMakerVolume,
                    ),
                    bottomWidget: BuyCoinSelectDropdown(
                      key: const Key('$keyPrefix-buy-select'),
                      buyCoin: state.buyCoin,
                      buyAmount: state.buyAmount,
                      coins: _filteredCoinsList(state.sellCoin.value),
                      onItemSelected: _onBuyCoinSelected,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DexInfoContainer(
                    children: [
                      PercentageInput(
                        key: const Key('$keyPrefix-trade-margin'),
                        label: Text(
                          '${LocaleKeys.margin.tr()}:',
                          style: theme.custom.tradingFormDetailsLabel,
                        ),
                        initialValue: state.tradeMargin.value,
                        onChanged: _onTradeMarginChanged,
                        errorText: state.tradeMargin.displayError?.text(
                          maxValue: 1000,
                        ),
                        maxIntegerDigits: 4,
                        maxFractionDigits: 5,
                      ),
                      const SizedBox(height: 8),
                      UpdateIntervalDropdown(
                        key: const Key('$keyPrefix-update-interval'),
                        label: Text(
                          '${LocaleKeys.updateInterval.tr()}:',
                          style: theme.custom.tradingFormDetailsLabel,
                        ),
                        interval: state.updateInterval.interval,
                        onChanged: _onUpdateIntervalChanged,
                      ),
                      const SizedBox(height: 12),
                      ExchangeRate(
                        key: const Key('$keyPrefix-exchange-rate'),
                        rate: state.priceFromUsdWithMarginRational,
                        base: state.sellCoin.value?.abbr,
                        rel: state.buyCoin.value?.abbr,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (state.tradePreImageError != null)
                    ImportantNote(
                      text: state.tradePreImageError?.textWithMin(
                            state.sellCoin.value,
                            state.buyCoin.value,
                            state.minTradingVolume?.toString(),
                          ) ??
                          '',
                    ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Flexible(
                        flex: 3,
                        child: UiLightButton(
                          key: const Key('$keyPrefix-clear-button'),
                          text: LocaleKeys.clear.tr(),
                          onPressed: _onClearFormPressed,
                          height: 40,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        flex: 7,
                        child: ConnectWalletWrapper(
                          key: const Key('$keyPrefix-connect-wallet-button'),
                          eventType: WalletsManagerEventType.dex,
                          child: AddMarketMakerBotTradeButton(
                            enabled: state.isValid,
                            onPressed: _onMakeOrderPressed,
                            sellCoin: state.sellCoin.value,
                            buyCoin: state.buyCoin.value,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Coin> _sellableCoins(List<Coin> coins) {
    // Sell list: must be active, have balance, and have fiat price
    return coins.where((coin) {
      final hasUsdPrice = (coin.usdPrice?.price?.toDouble() ?? 0.0) > 0.0;
      final hasBalance = (coin.lastKnownUsdBalance(context.sdk) ?? 0) > 0.0;
      return coin.isActive && hasUsdPrice && hasBalance;
    }).toList();
  }

  void _onMakeOrderPressed() {
    final tradeForm = context.read<MarketMakerTradeFormBloc>().state;
    final pairsCount =
        tradeForm.sellCoin.value != null && tradeForm.buyCoin.value != null
        ? 1
        : 0;
    context.read<AnalyticsBloc>().logEvent(
      MarketbotSetupStartedEventData(
        strategyType: 'simple',
        pairsCount: pairsCount,
      ),
    );

    context.read<MarketMakerTradeFormBloc>().add(
      const MarketMakerConfirmationPreviewRequested(),
    );
  }

  void _setSellCoinToDefaultCoin() {
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final defaultCoin = coinsRepository.getCoin(defaultDexCoin);
    final tradeFormBloc = context.read<MarketMakerTradeFormBloc>();
    if (defaultCoin != null && tradeFormBloc.state.sellCoin.value == null) {
      tradeFormBloc.add(MarketMakerTradeFormSellCoinChanged(defaultCoin));
    }
  }

  List<Coin> _filteredCoinsList(Coin? coin) {
    // Buy list: include all compatible coins with price data; exclude currently selected sell coin
    return widget.coins
        .where((e) => e.abbr != coin?.abbr)
        .where((e) => (e.usdPrice?.price?.toDouble() ?? 0.0) > 0.0)
        .toList();
  }

  void _onTradeMarginChanged(String value) {
    context.read<MarketMakerTradeFormBloc>().add(
      MarketMakerTradeFormTradeMarginChanged(value),
    );
  }

  void _onUpdateIntervalChanged(TradeBotUpdateInterval? value) {
    context.read<MarketMakerTradeFormBloc>().add(
      MarketMakerTradeFormUpdateIntervalChanged(
        value?.seconds.toString() ?? '',
      ),
    );
  }

  void _onClearFormPressed() {
    context.read<MarketMakerTradeFormBloc>().add(
      const MarketMakerTradeFormClearRequested(),
    );
  }

  void _onBuyCoinSelected(Coin? value) {
    context.read<MarketMakerTradeFormBloc>().add(
      MarketMakerTradeFormBuyCoinChanged(value),
    );
  }

  Future<bool> _swapBuyAndSellCoins() async {
    context.read<MarketMakerTradeFormBloc>().add(
      const MarketMakerTradeFormSwapCoinsRequested(),
    );
    return true;
  }

  void _onSelectSellCoin(Coin? value) {
    context.read<MarketMakerTradeFormBloc>().add(
      MarketMakerTradeFormSellCoinChanged(value),
    );
  }

  void _onVolumeRangeChanged(RangeValues values) {
    context.read<MarketMakerTradeFormBloc>().add(
      MarketMakerTradeFormTradeVolumeChanged(
        minimumTradeVolume: values.start,
        maximumTradeVolume: values.end,
      ),
    );
  }
}
