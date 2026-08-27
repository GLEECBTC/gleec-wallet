import 'package:app_theme/app_theme.dart';
import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/ui/custom_tooltip.dart';
import 'package:web_dex/shared/utils/extensions/transaction_extensions.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/views/wallet/common/address_copy_button.dart';
import 'package:web_dex/views/wallet/common/address_icon.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class TransactionListRow extends StatefulWidget {
  const TransactionListRow({
    Key? key,
    required this.transaction,
    required this.setTransaction,
    required this.coinAbbr,
  }) : super(key: key);

  final Transaction transaction;
  final String coinAbbr;
  final void Function(Transaction tx) setTransaction;

  @override
  State<TransactionListRow> createState() => _TransactionListRowState();
}

class _TransactionListRowState extends State<TransactionListRow> {
  bool get _isInternalTransfer => widget.transaction.isInternalTransfer;

  IconData get _icon {
    if (_isInternalTransfer) return Icons.swap_horiz;
    return _isReceived ? Icons.arrow_circle_down : Icons.arrow_circle_up;
  }

  Decimal get _displayAmount {
    final tx = widget.transaction;
    if (_isInternalTransfer) {
      // Unsigned magnitude moved between the wallet's own addresses.
      return tx.balanceChanges.spentByMe;
    }

    final netChange = tx.amount;
    if (netChange != Decimal.zero) {
      return netChange;
    }

    final received = tx.balanceChanges.receivedByMe;
    final spent = tx.balanceChanges.spentByMe;
    if (received != Decimal.zero || spent != Decimal.zero) {
      if (received >= spent) {
        return received;
      }
      return -spent;
    }

    if (tx.balanceChanges.totalAmount != Decimal.zero) {
      return tx.balanceChanges.totalAmount;
    }

    return Decimal.zero;
  }

  bool get _isReceived => _displayAmount > Decimal.zero;

  String get _sign {
    if (_isInternalTransfer) return '';
    return _isReceived ? '+' : '-';
  }

  String get _typeLabel {
    if (_isInternalTransfer) return LocaleKeys.txInternalTransfer.tr();
    return _isReceived ? LocaleKeys.receive.tr() : LocaleKeys.send.tr();
  }

  Color? _amountColor(BuildContext context) {
    if (_isInternalTransfer) {
      return Theme.of(context).textTheme.bodyMedium?.color;
    }
    return _isReceived
        ? theme.custom.increaseColor
        : theme.custom.decreaseColor;
  }

  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(16);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isMobile
            ? Theme.of(context).colorScheme.onSurface
            : Colors.transparent,
        borderRadius: borderRadius,
      ),
      child: InkWell(
        borderRadius: borderRadius,
        onFocusChange: (value) {
          setState(() {
            _hasFocus = value;
          });
        },
        hoverColor: Theme.of(context).primaryColor.withAlpha(20),
        child: Container(
          color: _hasFocus
              ? Theme.of(context).colorScheme.tertiary
              : Colors.transparent,
          margin: EdgeInsets.symmetric(vertical: isMobile ? 5 : 0),
          padding: isMobile
              ? const EdgeInsets.only(bottom: 12)
              : const EdgeInsets.all(6),
          child: isMobile ? _buildMobileRow(context) : _buildNormalRow(context),
        ),
        onTap: () => widget.setTransaction(widget.transaction),
      ),
    );
  }

  Widget _buildAmountChangesMobile(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_buildBalanceChanges(), _buildUsdChanges()],
    );
  }

  Widget _buildBalanceChanges() {
    final String formatted = formatDexAmt(_displayAmount.toDouble().abs());
    final Color? color = _amountColor(context);

    return Row(
      children: [
        Icon(_icon, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: AutoScrollText(
            text:
                '$formatted ${Coin.normalizeAbbr(widget.transaction.assetId.id)} ',
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceChangesMobile(BuildContext context) {
    return Row(
      children: [
        // Flexible so the (long) internal-transfer label wraps within the
        // row's cell instead of overflowing into the amount column.
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _typeLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                formatTransactionDateTime(widget.transaction),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMemoAndDate() {
    return Align(
      alignment: isMobile ? const Alignment(-1, 0) : const Alignment(1, 0),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildMemo(),
          const SizedBox(width: 6),
          Expanded(
            child: AutoScrollText(
              text: formatTransactionDateTime(widget.transaction),
              style: isMobile
                  ? TextStyle(color: Colors.grey[400])
                  : const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildMobileRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TransactionAddress(
            transaction: widget.transaction,
            coinAbbr: widget.coinAbbr,
          ),
          Row(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_buildBalanceChangesMobile(context)],
                ),
              ),
              Expanded(
                flex: 5,
                child: Align(
                  alignment: const Alignment(1, 0),
                  child: _buildAmountChangesMobile(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNormalRow(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        SizedBox(width: 8),
        Flexible(
          flex: 6,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 415),
            alignment: Alignment.centerLeft,
            child: _TransactionAddress(
              transaction: widget.transaction,
              coinAbbr: widget.coinAbbr,
            ),
          ),
        ),
        SizedBox(width: 16),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          // Constant width: a per-row 60/120 split made the amount and date
          // columns jog horizontally between adjacent rows whenever an
          // internal transfer sat in a mixed list.
          width: 120,
          child: Text(
            _typeLabel,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ),
        Expanded(flex: 4, child: _buildBalanceChanges()),
        Expanded(flex: 4, child: _buildUsdChanges()),
        Expanded(flex: 3, child: _buildMemoAndDate()),
      ],
    );
  }

  Widget _buildMemo() {
    final String? memo = widget.transaction.memo;
    if (memo == null || memo.isEmpty) return const SizedBox();

    return CustomTooltip(
      maxWidth: 200,
      tooltip: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${LocaleKeys.memo.tr()}:',
            style: theme.currentGlobal.textTheme.bodyLarge,
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: AutoScrollText(
              text: memo,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
      child: Icon(
        Icons.note,
        size: 14,
        color: theme.currentGlobal.colorScheme.onSurface,
      ),
    );
  }

  Widget _buildUsdChanges() {
    final coinsBloc = context.read<CoinsBloc>();
    final double? usdChanges = coinsBloc.state.getUsdPriceForAmount(
      _displayAmount.toDouble(),
      widget.coinAbbr,
    );
    final String prefix = _sign.isEmpty ? '' : '$_sign ';
    return AutoScrollText(
      text: '$prefix\$${formatAmt((usdChanges ?? 0).abs())}',
      style: TextStyle(
        color: _amountColor(context),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

extension _TransactionExtension on Transaction {
  String get myAddress {
    // Internal transfers show the destination; post-sanitize the wallet's
    // own (custody) address is sorted first in `to`.
    final List<String> addressList = isInternalTransfer || isIncoming
        ? to
        : from;
    return addressList.isNotEmpty ? addressList.first : LocaleKeys.unknown.tr();
  }
}

class _TransactionAddress extends StatelessWidget {
  const _TransactionAddress({
    required this.transaction,
    required this.coinAbbr,
  });

  final Transaction transaction;
  final String coinAbbr;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AddressIcon(address: transaction.myAddress),
        const SizedBox(width: 8),
        Expanded(
          child: AutoScrollText(
            text: transaction.myAddress,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: 4),
        AddressCopyButton(address: transaction.myAddress),
      ],
    );
  }
}
