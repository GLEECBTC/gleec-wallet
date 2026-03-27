import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/copied_text.dart';

class TransactionDetails extends StatelessWidget {
  const TransactionDetails({
    required this.transaction,
    required this.onClose,
    required this.coin,
    super.key,
  });

  final Transaction transaction;
  final void Function() onClose;
  final Coin coin;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = EdgeInsets.only(
      top: isMobile ? 16 : 0,
      left: 16,
      right: 16,
      bottom: isMobile ? 20 : 30,
    );
    final scrollController = ScrollController();

    return DexScrollbar(
      isMobile: isMobile,
      scrollController: scrollController,
      child: SingleChildScrollView(
        controller: scrollController,
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 550),
                padding: padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(0, 26, 0, 24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: theme.custom.subCardBackgroundColor,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            LocaleKeys.transactionDetailsTitle.tr(),
                            style: Theme.of(
                              context,
                            ).textTheme.titleLarge?.copyWith(fontSize: 18),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: AssetIcon.ofTicker(coin.abbr, size: 32),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: SelectableText(coin.displayName),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: _buildBalanceChanges(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    _buildSimpleData(
                      context,
                      title: LocaleKeys.date.tr(),
                      value: formatTransactionDateTime(transaction),
                      hasBackground: true,
                    ),
                    _buildFee(context),
                    _buildMemo(context),
                    _buildSimpleData(
                      context,
                      title: LocaleKeys.confirmations.tr(),
                      value: _confirmationsLabel(context),
                      hasBackground: true,
                    ),
                    _buildSimpleData(
                      context,
                      title: LocaleKeys.blockHeight.tr(),
                      value: _blockHeightLabel(),
                    ),
                    _buildSimpleData(
                      context,
                      title: LocaleKeys.transactionHash.tr(),
                      value: transaction.txHash ?? '',
                      isCopied: true,
                      isTruncated: true,
                    ),
                    SizedBox(height: 16),
                    _buildSimpleData(
                      context,
                      title: LocaleKeys.from.tr(),
                      value: transaction.from.isEmpty
                          ? LocaleKeys.zhtlcShieldedAddress.tr()
                          : transaction.from.first,
                      isCopied: true,
                    ),
                    _buildSimpleData(
                      context,
                      title: LocaleKeys.to.tr(),
                      value: transaction.to.isEmpty
                          ? LocaleKeys.zhtlcShieldedAddress.tr()
                          : transaction.to.first,
                      isCopied: true,
                    ),
                    SizedBox(height: 16),
                    _buildControls(context, isMobile),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _confirmationsLabel(BuildContext context) {
    final confirmations = transaction.confirmations;
    if (confirmations > 0) {
      return confirmations.toString();
    }

    if (transaction.blockHeight > 0) {
      return '0';
    }

    return LocaleKeys.inProgress.tr();
  }

  String _blockHeightLabel() {
    if (transaction.blockHeight > 0) {
      return transaction.blockHeight.toString();
    }
    return LocaleKeys.unknown.tr();
  }

  Widget _buildBalanceChanges(BuildContext context) {
    final String formatted = formatDexAmt(transaction.amount.toDouble().abs());
    final String sign = transaction.amount.toDouble() > 0 ? '+' : '-';
    final coinsBloc = RepositoryProvider.of<CoinsRepo>(context);
    final double? usd = coinsBloc.getUsdPriceForAmount(
      transaction.amount.toDouble().abs(),
      transaction.assetId.id,
    );
    final String formattedUsd = formatAmt(usd ?? 0);
    final String value =
        '$sign $formatted ${Coin.normalizeAbbr(transaction.assetId.id)} (\$$formattedUsd)';

    return SelectableText(
      value,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontSize: 22,
        color: theme.custom.balanceColor,
      ),
    );
  }

  Widget _buildControls(BuildContext context, bool isMobile) {
    final double buttonHeight = isMobile ? 50 : 40;
    final double buttonWidth = isMobile ? 130 : 150;
    final double fontSize = isMobile ? 12 : 14;
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        UiPrimaryButton(
          width: buttonWidth,
          height: buttonHeight,
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: fontSize,
            color: theme.custom.defaultGradientButtonTextColor,
          ),
          onPressed: () {
            launchURLString(getTxExplorerUrl(coin, transaction.txHash ?? ''));
          },
          text: LocaleKeys.viewOnExplorer.tr(),
        ),
        SizedBox(width: isMobile ? 4 : 20),
        UiPrimaryButton(
          width: buttonWidth,
          height: buttonHeight,
          onPressed: onClose,
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
          ),
          backgroundColor: theme.custom.lightButtonColor,
          text: LocaleKeys.done.tr(),
        ),
      ],
    );
  }

  Widget _buildFee(BuildContext context) {
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final String title = LocaleKeys.fees.tr();

    final String value;
    final TextStyle? valueStyle;

    if (transaction.fee == null) {
      value = '\u2014';
      valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      );
    } else {
      final fee = transaction.fee!;
      final String feeAmount = formatDexAmt(fee.totalFee.toDouble());
      final double? usd = coinsRepository.getUsdPriceForAmount(
        fee.totalFee.toDouble(),
        _feeCoin,
      );
      final String formattedUsd = formatAmt(usd ?? 0);
      value = '- ${Coin.normalizeAbbr(_feeCoin)} $feeAmount (\$$formattedUsd)';
      valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: theme.custom.decreaseColor,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 15.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontSize: 14),
            ),
          ),
          Expanded(
            flex: 6,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 35),
              alignment: Alignment.centerLeft,
              child: SelectableText(value, style: valueStyle),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemo(BuildContext context) {
    final String? memo = transaction.memo;
    if (memo == null || memo.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 15.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              '${LocaleKeys.memo.tr()}: ',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontSize: 14),
            ),
          ),
          Expanded(
            flex: 6,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 35),
              alignment: Alignment.centerLeft,
              child: SelectableText(
                memo,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleData(
    BuildContext context, {
    required String title,
    required String value,
    bool hasBackground = false,
    bool isCopied = false,
    bool isTruncated = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontSize: 14),
            ),
          ),
          Expanded(
            flex: 6,
            child: Align(
              alignment: Alignment.centerLeft,
              child: isCopied
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: CopiedText(
                        copiedValue: value,
                        isTruncated: isTruncated,
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                        fontSize: 14,
                      ),
                    )
                  : SelectableText(
                      value,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontSize: 14),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String get _feeCoin {
    return transaction.fee != null && transaction.fee!.coin.isNotEmpty
        ? transaction.fee!.coin
        : transaction.assetId.id;
  }
}
