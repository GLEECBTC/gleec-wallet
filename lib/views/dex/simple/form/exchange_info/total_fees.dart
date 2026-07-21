import 'dart:math';

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/trade_preimage.dart';
import 'package:web_dex/model/trade_preimage_extended_fee_info.dart';
import 'package:web_dex/shared/ui/custom_tooltip.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';

class TotalFees extends StatefulWidget {
  const TotalFees({Key? key, required this.preimage}) : super(key: key);

  final TradePreimage? preimage;

  @override
  State<TotalFees> createState() => _TotalFeesState();
}

class _TotalFeesState extends State<TotalFees> {
  @override
  Widget build(BuildContext context) {
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final colors = GleecColorTokens.of(context);
    final typography = GleecTypography.of(context);
    return Row(
      children: [
        Text(LocaleKeys.totalFees.tr(), style: typography.bodySmall),
        const SizedBox(width: 7),
        widget.preimage == null
            ? const SizedBox.shrink()
            : CustomTooltip(
                tooltip: _buildDetails(),
                maxWidth: min(350, screenWidth - 140),
                child: SvgPicture.asset(
                  '$assetsPath/others/round_question_mark.svg',
                  colorFilter: ColorFilter.mode(
                    colors.textTertiary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
        Expanded(
          child: Container(
            alignment: Alignment.centerRight,
            child: AutoScrollText(
              text: getTotalFee(
                widget.preimage?.totalFees,
                coinsRepository.getCoin,
              ),
              style: typography.tabularAmountCompact,
            ),
          ),
        ),
      ],
    );
  }

  Widget? _buildDetails() {
    if (widget.preimage == null) return null;

    return Column(
      children: [
        _buildPaidFromBalance(),
        const SizedBox(height: 4),
        _buildPaidFromTrade(),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildPaidFromBalance() {
    final TradePreimage? preimage = widget.preimage;
    if (preimage == null) return const SizedBox.shrink();

    final TradePreimageExtendedFeeInfo? takerFee = preimage.takerFee;
    final TradePreimageExtendedFeeInfo? feeToSendTakerFee =
        preimage.feeToSendTakerFee;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
          color: Theme.of(context).highlightColor.withAlpha(25),
          child: SelectableText(
            LocaleKeys.swapFeeDetailsPaidFromBalance.tr(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 4),
        if (!preimage.baseCoinFee.paidFromTradingVol)
          Container(
            padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
            child: SelectableText(
              '• ${cutTrailingZeros(formatAmt(double.tryParse(preimage.baseCoinFee.amount) ?? 0))} '
              '${preimage.baseCoinFee.coin} '
              '(${getFormattedFiatAmount(context, preimage.baseCoinFee.coin, preimage.baseCoinFee.amountRational, 8)}): '
              '${LocaleKeys.swapFeeDetailsSendCoinTxFee.tr(args: [preimage.baseCoinFee.coin])}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (!preimage.relCoinFee.paidFromTradingVol)
          Container(
            padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
            child: SelectableText(
              '• ${cutTrailingZeros(formatAmt(double.tryParse(preimage.relCoinFee.amount) ?? 0))} '
              '${preimage.relCoinFee.coin} '
              '(${getFormattedFiatAmount(context, preimage.relCoinFee.coin, preimage.relCoinFee.amountRational, 8)}): '
              '${LocaleKeys.swapFeeDetailsReceiveCoinTxFee.tr(args: [preimage.relCoinFee.coin])}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (takerFee != null && !takerFee.paidFromTradingVol)
          Container(
            padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
            child: SelectableText(
              '• ${cutTrailingZeros(formatAmt(double.tryParse(takerFee.amount) ?? 0))} '
              '${takerFee.coin} '
              '(${getFormattedFiatAmount(context, takerFee.coin, takerFee.amountRational, 8)}): '
              '${LocaleKeys.swapFeeDetailsTradingFee.tr()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (feeToSendTakerFee != null && !feeToSendTakerFee.paidFromTradingVol)
          Container(
            padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
            child: SelectableText(
              '• ${cutTrailingZeros(formatAmt(double.tryParse(feeToSendTakerFee.amount) ?? 0))} '
              '${feeToSendTakerFee.coin} '
              '(${getFormattedFiatAmount(context, feeToSendTakerFee.coin, feeToSendTakerFee.amountRational, 8)}): '
              '${LocaleKeys.swapFeeDetailsSendTradingFeeTxFee.tr()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _buildPaidFromTrade() {
    final TradePreimage? preimage = widget.preimage;
    if (preimage == null) return const SizedBox.shrink();

    final TradePreimageExtendedFeeInfo? takerFee = preimage.takerFee;
    final TradePreimageExtendedFeeInfo? feeToSendTakerFee =
        preimage.feeToSendTakerFee;
    final List<Widget> items = [];

    if (preimage.baseCoinFee.paidFromTradingVol) {
      items.add(
        Container(
          padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
          child: SelectableText(
            '• ${cutTrailingZeros(formatAmt(double.tryParse(preimage.baseCoinFee.amount) ?? 0))} '
            '${preimage.baseCoinFee.coin} '
            '(${getFormattedFiatAmount(context, preimage.baseCoinFee.coin, preimage.baseCoinFee.amountRational, 8)}): '
            '${LocaleKeys.swapFeeDetailsSendCoinTxFee.tr(args: [preimage.baseCoinFee.coin])}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    if (preimage.relCoinFee.paidFromTradingVol) {
      items.add(
        Container(
          padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
          child: SelectableText(
            '• ${cutTrailingZeros(formatAmt(double.tryParse(preimage.relCoinFee.amount) ?? 0))} '
            '${preimage.relCoinFee.coin} '
            '(${getFormattedFiatAmount(context, preimage.relCoinFee.coin, preimage.relCoinFee.amountRational, 8)}): '
            '${LocaleKeys.swapFeeDetailsReceiveCoinTxFee.tr(args: [preimage.relCoinFee.coin])}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    if (takerFee != null && takerFee.paidFromTradingVol) {
      items.add(
        Container(
          padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
          child: SelectableText(
            '• ${cutTrailingZeros(formatAmt(double.tryParse(takerFee.amount) ?? 0))} '
            '${takerFee.coin} '
            '(${getFormattedFiatAmount(context, takerFee.coin, takerFee.amountRational, 8)}): '
            '${LocaleKeys.swapFeeDetailsTradingFee.tr()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    if (feeToSendTakerFee != null && feeToSendTakerFee.paidFromTradingVol) {
      items.add(
        Container(
          padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
          child: SelectableText(
            '• ${cutTrailingZeros(formatAmt(double.tryParse(feeToSendTakerFee.amount) ?? 0))} '
            '${feeToSendTakerFee.coin} '
            '(${getFormattedFiatAmount(context, feeToSendTakerFee.coin, feeToSendTakerFee.amountRational, 8)}): '
            '${LocaleKeys.swapFeeDetailsSendTradingFeeTxFee.tr()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    if (items.isEmpty) {
      items.add(
        Container(
          padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
          child: SelectableText(
            '• ${LocaleKeys.swapFeeDetailsNone.tr()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
          color: Theme.of(context).highlightColor.withAlpha(25),
          child: SelectableText(
            LocaleKeys.swapFeeDetailsPaidFromReceivedVolume.tr(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 4),
        ...items,
      ],
    );
  }
}
