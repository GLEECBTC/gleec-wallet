import 'package:app_theme/app_theme.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/system_health/system_health_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/bloc/taker_form/taker_state.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/ui/ui_light_button.dart';
import 'package:web_dex/shared/widgets/connect_wallet/connect_wallet_wrapper.dart';
import 'package:web_dex/views/dex/common/form_plate.dart';
import 'package:web_dex/views/dex/common/section_switcher.dart';
import 'package:web_dex/views/dex/simple/form/common/dex_flip_button_overlapper.dart';
import 'package:web_dex/views/dex/simple/form/taker/coin_item/taker_form_buy_item.dart';
import 'package:web_dex/views/dex/simple/form/taker/coin_item/taker_form_sell_item.dart';
import 'package:web_dex/views/dex/simple/form/taker/taker_form_error_list.dart';
import 'package:web_dex/views/dex/simple/form/taker/taker_form_exchange_info.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';

class TakerFormContent extends StatelessWidget {
  const TakerFormContent({super.key});

  @override
  Widget build(BuildContext context) {
    return FormPlate(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 12),
          SectionSwitcher(),
          const SizedBox(height: 6),
          DexFlipButtonOverlapper(
            onTap: () async {
              final takerBloc = context.read<TakerBloc>();
              final selectedOrder = takerBloc.state.selectedOrder;
              if (selectedOrder == null) return false;

              final coinsRepo = RepositoryProvider.of<CoinsRepo>(context);
              final knownCoins = coinsRepo.getKnownCoins();
              final buyCoin = knownCoins.firstWhereOrNull(
                (element) => element.abbr == selectedOrder.coin,
              );
              if (buyCoin == null) return false;

              takerBloc.add(
                TakerSetSellCoin(
                  buyCoin,
                  autoSelectOrderAbbr: takerBloc.state.sellCoin?.abbr,
                ),
              );
              return true;
            },
            topWidget: const TakerFormSellItem(),
            bottomWidget: const TakerFormBuyItem(),
          ),
          const TakerFormErrorList(),
          const SizedBox(height: 24),
          const TakerFormExchangeInfo(),
          const SizedBox(height: 24),
          const _FormControls(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _FormControls extends StatelessWidget {
  const _FormControls();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: theme.custom.dexFormWidth - 32),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ResetSwapFormButton(),
          const SizedBox(width: 10),
          Expanded(
            child: ConnectWalletWrapper(
              key: const Key('connect-wallet-taker-form'),
              eventType: WalletsManagerEventType.dex,
              buttonSize: Size(112, isMobile ? 52 : 40),
              child: const TradeButton(),
            ),
          ),
        ],
      ),
    );
  }
}

class ResetSwapFormButton extends StatelessWidget {
  const ResetSwapFormButton({super.key});

  @override
  Widget build(BuildContext context) {
    return UiLightButton(
      width: 112,
      height: isMobile ? 52 : 40,
      text: LocaleKeys.clear.tr(),
      onPressed: () => context.read<TakerBloc>().add(TakerClear()),
    );
  }
}

class TradeButton extends StatelessWidget {
  const TradeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SystemHealthBloc, SystemHealthState>(
      builder: (context, systemHealthState) {
        final bool isSystemClockValid =
            systemHealthState is SystemHealthLoadSuccess &&
            systemHealthState.isValid;

        final tradingStatusState = context.watch<TradingStatusBloc>().state;
        final takerState = context.watch<TakerBloc>().state;
        final coinsRepo = RepositoryProvider.of<CoinsRepo>(context);
        final buyCoin = takerState.selectedOrder == null
            ? null
            : coinsRepo.getCoin(takerState.selectedOrder!.coin);

        final isTradingEnabled = tradingStatusState.canTradeAssets([
          takerState.sellCoin?.id,
          buyCoin?.id,
        ]);

        return BlocSelector<TakerBloc, TakerState, bool>(
          selector: (state) => state.inProgress,
          builder: (context, inProgress) {
            final bool disabled = inProgress || !isSystemClockValid;

            return Opacity(
              opacity: disabled ? 0.8 : 1,
              child: UiPrimaryButton(
                key: const Key('take-order-button'),
                text: isTradingEnabled
                    ? LocaleKeys.swapNow.tr()
                    : LocaleKeys.tradingDisabled.tr(),
                prefix: inProgress ? const TradeButtonSpinner() : null,
                child: _DexTradeButtonContent(
                  text: isTradingEnabled
                      ? LocaleKeys.swapNow.tr()
                      : LocaleKeys.tradingDisabled.tr(),
                  prefix: inProgress ? const TradeButtonSpinner() : null,
                ),
                onPressed: disabled || !isTradingEnabled
                    ? null
                    : () =>
                          context.read<TakerBloc>().add(TakerFormSubmitClick()),
                height: isMobile ? 52 : 40,
              ),
            );
          },
        );
      },
    );
  }
}

class TradeButtonSpinner extends StatelessWidget {
  const TradeButtonSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(right: 4),
      child: UiSpinner(
        width: 10,
        height: 10,
        strokeWidth: 1,
        color: theme.custom.defaultGradientButtonTextColor,
      ),
    );
  }
}

class _DexTradeButtonContent extends StatelessWidget {
  const _DexTradeButtonContent({required this.text, this.prefix});

  final String text;
  final Widget? prefix;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (prefix != null) prefix!,
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(text, maxLines: 1, textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}
