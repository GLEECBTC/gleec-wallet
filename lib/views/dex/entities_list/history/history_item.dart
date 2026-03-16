import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/shared/ui/ui_light_button.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/widgets/focusable_widget.dart';
import 'package:web_dex/views/dex/entities_list/common/coin_amount_mobile.dart';
import 'package:web_dex/views/dex/entities_list/common/entity_item_status_wrapper.dart';
import 'package:web_dex/views/dex/entities_list/common/swap_actions_menu.dart';
import 'package:web_dex/views/dex/entities_list/common/trade_amount_desktop.dart';

class HistoryItem extends StatefulWidget {
  const HistoryItem(this.swap, {Key? key, required this.onClick})
    : super(key: key);

  final Swap swap;
  final VoidCallback onClick;

  @override
  State<HistoryItem> createState() => _HistoryItemState();
}

class _HistoryItemState extends State<HistoryItem> {
  bool _isRecovering = false;

  @override
  Widget build(BuildContext context) {
    final String uuid = widget.swap.uuid;
    final String sellCoin = widget.swap.sellCoin;
    final Rational sellAmount = widget.swap.sellAmount;
    final String buyCoin = widget.swap.buyCoin;
    final Rational buyAmount = widget.swap.buyAmount;
    final String date = widget.swap.myInfo != null
        ? getFormattedDate(widget.swap.myInfo!.startedAt)
        : '-';
    final bool isSuccessful = !widget.swap.isFailed;
    final bool isTaker = widget.swap.isTaker;
    final bool isRecoverable = widget.swap.recoverable;
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isMobile)
          Text(
            tradingEntitiesBloc.getTypeString(isTaker),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _typeColor,
            ),
          ),
        FocusableWidget(
          key: Key('swap-item-$uuid'),
          onTap: widget.onClick,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Theme.of(context).colorScheme.onSurface,
            ),
            child: isMobile
                ? _HistoryItemMobile(
                    key: Key('swap-item-$uuid-mobile'),
                    swap: widget.swap,
                    uuid: uuid,
                    isRecovering: _isRecovering,
                    buyAmount: buyAmount,
                    buyCoin: buyCoin,
                    date: date,
                    isSuccessful: isSuccessful,
                    sellAmount: sellAmount,
                    sellCoin: sellCoin,
                    onRecoverPressed: isRecoverable ? _onRecoverPressed : null,
                  )
                : _HistoryItemDesktop(
                    key: Key('swap-item-$uuid-desktop'),
                    uuid: uuid,
                    isRecovering: _isRecovering,
                    buyAmount: buyAmount,
                    buyCoin: buyCoin,
                    date: date,
                    isSuccessful: isSuccessful,
                    isTaker: isTaker,
                    sellAmount: sellAmount,
                    sellCoin: sellCoin,
                    typeColor: _typeColor,
                    onRecoverPressed: isRecoverable ? _onRecoverPressed : null,
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _onRecoverPressed() async {
    if (_isRecovering) return;
    setState(() {
      _isRecovering = true;
    });
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    await tradingEntitiesBloc.recoverFundsOfSwap(widget.swap.uuid);
    setState(() {
      _isRecovering = false;
    });
  }

  Color get _typeColor => widget.swap.isTaker
      ? theme.custom.dexPageTheme.takerLabelColor
      : theme.custom.dexPageTheme.makerLabelColor;
}

class _HistoryItemDesktop extends StatelessWidget {
  const _HistoryItemDesktop({
    Key? key,
    required this.uuid,
    required this.isRecovering,
    required this.sellCoin,
    required this.buyCoin,
    required this.sellAmount,
    required this.buyAmount,
    required this.isSuccessful,
    required this.isTaker,
    required this.date,
    required this.typeColor,
    required this.onRecoverPressed,
  }) : super(key: key);
  final String uuid;

  final bool isRecovering;
  final String sellCoin;
  final Rational sellAmount;
  final String buyCoin;
  final Rational buyAmount;
  final bool isSuccessful;
  final bool isTaker;
  final String date;
  final Color typeColor;
  final VoidCallback? onRecoverPressed;

  @override
  Widget build(BuildContext context) {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: EntityItemStatusWrapper(
                  text: isSuccessful
                      ? LocaleKeys.successful.tr()
                      : LocaleKeys.failed.tr(),
                  width: 100,
                  icon: isSuccessful
                      ? Icon(
                          Icons.check,
                          size: 12,
                          color: theme
                              .custom
                              .dexPageTheme
                              .successfulSwapStatusColor,
                        )
                      : Icon(
                          Icons.circle,
                          size: 12,
                          color:
                              theme.custom.dexPageTheme.failedSwapStatusColor,
                        ),
                  textColor: isSuccessful
                      ? theme.custom.dexPageTheme.successfulSwapStatusColor
                      : Theme.of(context).textTheme.bodyMedium?.color,
                  backgroundColor: isSuccessful
                      ? theme
                            .custom
                            .dexPageTheme
                            .successfulSwapStatusBackgroundColor
                      : Theme.of(context).colorScheme.surface,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          key: Key('history-item-$uuid-sell-amount'),
          child: TradeAmountDesktop(coinAbbr: sellCoin, amount: sellAmount),
        ),
        Expanded(
          child: TradeAmountDesktop(coinAbbr: buyCoin, amount: buyAmount),
        ),
        Expanded(
          child: Text(
            formatAmt(
              tradingEntitiesBloc.getPriceFromAmount(sellAmount, buyAmount),
            ),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Text(
            date,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          flex: 0,
          child: Text(
            tradingEntitiesBloc.getTypeString(isTaker),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: typeColor,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 6.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              onRecoverPressed != null
                  ? UiLightButton(
                      width: 80,
                      height: 22,
                      backgroundColor: theme.currentGlobal.colorScheme.error,
                      text: isRecovering ? '' : LocaleKeys.recover.tr(),
                      prefix: isRecovering
                          ? const UiSpinner(
                              width: 12,
                              height: 12,
                              color: Colors.orange,
                            )
                          : null,
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                      onPressed: onRecoverPressed,
                    )
                  : const SizedBox(width: 80),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryItemMobile extends StatelessWidget {
  const _HistoryItemMobile({
    Key? key,
    required this.swap,
    required this.uuid,
    required this.isRecovering,
    required this.sellCoin,
    required this.buyCoin,
    required this.sellAmount,
    required this.buyAmount,
    required this.isSuccessful,
    required this.date,
    required this.onRecoverPressed,
  }) : super(key: key);
  final Swap swap;
  final String uuid;
  final bool isRecovering;
  final String sellCoin;
  final Rational sellAmount;
  final String buyCoin;
  final Rational buyAmount;
  final bool isSuccessful;
  final String date;
  final VoidCallback? onRecoverPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LocaleKeys.send.tr(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: CoinAmountMobile(
                      coinAbbr: sellCoin,
                      amount: sellAmount,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onRecoverPressed != null)
                  UiLightButton(
                    width: 70,
                    height: 22,
                    prefix: isRecovering
                        ? const UiSpinner(color: Colors.orange)
                        : null,
                    backgroundColor:
                        theme.custom.dexPageTheme.failedSwapStatusColor,
                    text: isRecovering ? '' : LocaleKeys.recover.tr(),
                    textStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                    onPressed: onRecoverPressed,
                  ),
                if (onRecoverPressed != null) const SizedBox(width: 4),
                SwapActionsMenu(swap: swap),
              ],
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            LocaleKeys.receive.tr(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: CoinAmountMobile(coinAbbr: buyCoin, amount: buyAmount),
              ),
              Text(
                date,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.all(12),
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: isSuccessful
                ? theme.custom.dexPageTheme.successfulSwapStatusBackgroundColor
                : Theme.of(context).colorScheme.surface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              isSuccessful
                  ? Icon(
                      Icons.check,
                      size: 12,
                      color:
                          theme.custom.dexPageTheme.successfulSwapStatusColor,
                    )
                  : Icon(
                      Icons.circle,
                      size: 12,
                      color: theme.custom.dexPageTheme.failedSwapStatusColor,
                    ),
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Text(
                  isSuccessful
                      ? LocaleKeys.successful.tr()
                      : LocaleKeys.failed.tr(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
