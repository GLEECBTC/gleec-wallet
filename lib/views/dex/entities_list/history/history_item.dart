import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/shared/ui/ui_light_button.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/widgets/focusable_widget.dart';
import 'package:web_dex/views/dex/common/dex_confirmation_dialog.dart';
import 'package:web_dex/views/dex/common/dex_responsive.dart';
import 'package:web_dex/views/dex/entities_list/common/coin_amount_mobile.dart';
import 'package:web_dex/views/dex/entities_list/common/entity_item_status_wrapper.dart';
import 'package:web_dex/views/dex/entities_list/common/swap_actions_menu.dart';
import 'package:web_dex/views/dex/entities_list/common/trade_amount_desktop.dart';

class HistoryItem extends StatefulWidget {
  const HistoryItem(this.swap, {super.key, required this.onClick});

  final Swap swap;
  final VoidCallback onClick;

  @override
  State<HistoryItem> createState() => _HistoryItemState();
}

class _HistoryItemState extends State<HistoryItem> {
  bool _isRecovering = false;
  String? _recoveryResult;

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);
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

    return StreamBuilder<Map<String, RecoverySubmissionStatus>>(
      initialData: const {},
      stream: tradingEntitiesBloc.outRecoveryStatuses,
      builder: (context, recoverySnapshot) {
        final recoveryStatus =
            recoverySnapshot.data?[uuid] ??
            tradingEntitiesBloc.recoveryStatusFor(uuid);
        final recoveryLocked = recoveryStatus != RecoverySubmissionStatus.idle;
        final recovering =
            _isRecovering ||
            recoveryStatus == RecoverySubmissionStatus.submitting;
        final recoveryMessage = switch (recoveryStatus) {
          RecoverySubmissionStatus.accepted => 'advancedRecoverySubmitted'.tr(),
          RecoverySubmissionStatus.uncertain =>
            'advancedRecoveryUncertain'.tr(),
          RecoverySubmissionStatus.submitting =>
            'advancedRecoverySubmitting'.tr(),
          RecoverySubmissionStatus.idle => _recoveryResult,
        };
        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = DexResponsiveSpec.fromWidth(
              constraints.maxWidth,
            ).usesMobileLists;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isCompact)
                  Text(
                    tradingEntitiesBloc.getTypeString(isTaker),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isTaker ? colors.info : colors.brand,
                    ),
                  ),
                FocusableWidget(
                  key: ValueKey<int>(uuid.hashCode),
                  onTap: widget.onClick,
                  borderRadius: geometry.borderRadius16,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 12, 6, 12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      borderRadius: geometry.borderRadius16,
                      color: colors.surfaceRaised,
                      border: Border.all(color: colors.border),
                    ),
                    child: isCompact
                        ? _HistoryItemMobile(
                            key: ValueKey<int>(Object.hash(uuid, 'mobile')),
                            swap: widget.swap,
                            uuid: uuid,
                            isRecovering: recovering,
                            buyAmount: buyAmount,
                            buyCoin: buyCoin,
                            date: date,
                            isSuccessful: isSuccessful,
                            sellAmount: sellAmount,
                            sellCoin: sellCoin,
                            onRecoverPressed:
                                isRecoverable &&
                                    !recoveryLocked &&
                                    tradingEntitiesBloc.canRecoverSwap(uuid)
                                ? _onRecoverPressed
                                : null,
                          )
                        : _HistoryItemDesktop(
                            key: ValueKey<int>(Object.hash(uuid, 'desktop')),
                            uuid: uuid,
                            isRecovering: recovering,
                            buyAmount: buyAmount,
                            buyCoin: buyCoin,
                            date: date,
                            isSuccessful: isSuccessful,
                            isTaker: isTaker,
                            sellAmount: sellAmount,
                            sellCoin: sellCoin,
                            typeColor: isTaker ? colors.info : colors.brand,
                            onRecoverPressed:
                                isRecoverable &&
                                    !recoveryLocked &&
                                    tradingEntitiesBloc.canRecoverSwap(uuid)
                                ? _onRecoverPressed
                                : null,
                          ),
                  ),
                ),
                if (recoveryMessage case final message?)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(message),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _onRecoverPressed() async {
    if (_isRecovering) return;
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    if (tradingEntitiesBloc.recoveryStatusFor(widget.swap.uuid) !=
            RecoverySubmissionStatus.idle ||
        !tradingEntitiesBloc.canRecoverSwap(widget.swap.uuid)) {
      return;
    }
    final confirmed = await showDexActionConfirmation(
      context: context,
      actionLabel: LocaleKeys.recover.tr(),
      targetDescription:
          '${widget.swap.sellCoin}/${widget.swap.buyCoin} swap\n'
          '${widget.swap.uuid}',
      confirmButtonKey: const Key('dex-history-recover-confirm'),
    );
    if (!confirmed || !mounted) return;
    if (tradingEntitiesBloc.recoveryStatusFor(widget.swap.uuid) !=
            RecoverySubmissionStatus.idle ||
        !tradingEntitiesBloc.canRecoverSwap(widget.swap.uuid)) {
      return;
    }
    setState(() {
      _isRecovering = true;
    });
    Object? result;
    try {
      result = await tradingEntitiesBloc.recoverFundsOfSwap(widget.swap.uuid);
    } on Object {
      result = null;
    }
    if (!mounted) return;
    final recoveryStatus = tradingEntitiesBloc.recoveryStatusFor(
      widget.swap.uuid,
    );
    setState(() {
      _isRecovering = false;
      _recoveryResult = switch (recoveryStatus) {
        RecoverySubmissionStatus.accepted => 'advancedRecoverySubmitted'.tr(),
        RecoverySubmissionStatus.uncertain => 'advancedRecoveryUncertain'.tr(),
        RecoverySubmissionStatus.submitting =>
          'advancedRecoverySubmitting'.tr(),
        RecoverySubmissionStatus.idle =>
          result == null
              ? 'advancedRecoveryFailed'.tr()
              : 'advancedRecoverySubmitted'.tr(),
      };
    });
  }
}

class _HistoryItemDesktop extends StatelessWidget {
  const _HistoryItemDesktop({
    super.key,
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
  });
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
    final colors = GleecColorTokens.of(context);
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
                      ? Icon(Icons.check, size: 12, color: colors.success)
                      : Icon(Icons.circle, size: 12, color: colors.danger),
                  textColor: isSuccessful
                      ? colors.success
                      : colors.textSecondary,
                  backgroundColor: isSuccessful
                      ? colors.successContainer
                      : colors.dangerContainer,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          key: ValueKey<int>(Object.hash('history-sell-amount', uuid)),
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
                      width: 112,
                      height: 48,
                      backgroundColor: colors.dangerContainer,
                      text: isRecovering ? '' : LocaleKeys.recover.tr(),
                      prefix: isRecovering
                          ? UiSpinner(
                              width: 12,
                              height: 12,
                              color: colors.danger,
                            )
                          : null,
                      textStyle: TextStyle(color: colors.danger),
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
    super.key,
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
  });
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
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);
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
                    width: 112,
                    height: 48,
                    prefix: isRecovering
                        ? UiSpinner(color: colors.danger)
                        : null,
                    backgroundColor: colors.dangerContainer,
                    text: isRecovering ? '' : LocaleKeys.recover.tr(),
                    textStyle: TextStyle(color: colors.danger),
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
            borderRadius: geometry.borderRadius12,
            color: isSuccessful
                ? colors.successContainer
                : colors.dangerContainer,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              isSuccessful
                  ? Icon(Icons.check, size: 12, color: colors.success)
                  : Icon(Icons.circle, size: 12, color: colors.danger),
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
