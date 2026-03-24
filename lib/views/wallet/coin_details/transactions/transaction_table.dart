import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui/komodo_ui.dart' show showAddressSearch;
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_bloc.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_bloc.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/wallet/coin_details/transactions/transaction_details.dart';
import 'package:web_dex/views/wallet/coin_details/transactions/transaction_list.dart';

class TransactionTable extends StatelessWidget {
  const TransactionTable({
    Key? key,
    required this.coin,
    required this.setTransaction,
    this.selectedTransaction,
  }) : super(key: key);

  final Coin coin;
  final Transaction? selectedTransaction;
  final Function(Transaction?) setTransaction;

  @override
  Widget build(BuildContext context) {
    if (coin.isSuspended) {
      return SliverToBoxAdapter(
        child: _ErrorMessage(
          text: LocaleKeys.txHistoryNoTransactions.tr(),
          textColor: theme.currentGlobal.textTheme.bodyLarge?.color,
        ),
      );
    }

    final isTxHistorySupported = hasTxHistorySupport(coin);
    if (!isTxHistorySupported) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: _IguanaCoinWithoutTxHistorySupport(coin: coin),
        ),
      );
    }

    final Transaction? selectedTx = selectedTransaction;

    if (selectedTx == null) {
      return _buildTransactionList(context);
    }

    return _buildTransactionDetails(selectedTx);
  }

  Widget _buildTransactionDetails(Transaction tx) {
    return SliverToBoxAdapter(
      child: TransactionDetails(
        transaction: tx,
        coin: coin,
        onClose: () => setTransaction(null),
      ),
    );
  }

  Widget _buildTransactionList(BuildContext context) {
    return BlocBuilder<TransactionHistoryBloc, TransactionHistoryState>(
      builder: (BuildContext ctx, TransactionHistoryState state) {
        if (state.transactions.isEmpty && state.loading) {
          return const SliverToBoxAdapter(child: UiSpinnerList());
        }

        if (state.error != null) {
          String errorText;
          if (state.error!.message.contains('Asset activation failed')) {
            errorText = 'Asset activation failed for ${coin.displayName}';
          } else {
            errorText = LocaleKeys.connectionToServersFailing.tr(
              args: [coin.displayName],
            );
          }

          return SliverToBoxAdapter(
            child: _ErrorMessage(
              text: errorText,
              textColor: theme.currentGlobal.colorScheme.error,
            ),
          );
        }

        return _TransactionsListWrapper(
          coinAbbr: coin.abbr,
          setTransaction: setTransaction,
          transactions: state.transactions,
          isInProgress: state.loading,
        );
      },
    );
  }
}

class _TransactionsListWrapper extends StatelessWidget {
  const _TransactionsListWrapper({
    required this.coinAbbr,
    required this.transactions,
    required this.setTransaction,
    required this.isInProgress,
  });

  final String coinAbbr;
  final List<Transaction> transactions;
  final bool isInProgress;
  final void Function(Transaction tx) setTransaction;

  @override
  Widget build(BuildContext context) {
    return TransactionList(
      coinAbbr: coinAbbr,
      transactions: transactions,
      isInProgress: isInProgress,
      setTransaction: setTransaction,
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({Key? key, required this.text, this.textColor})
    : super(key: key);
  final String text;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return DexScrollbar(
      scrollController: scrollController,
      child: SingleChildScrollView(
        controller: scrollController,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 185),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: theme.currentGlobal.colorScheme.onSurface,
            ),
            padding: const EdgeInsets.symmetric(vertical: 20),
            margin: const EdgeInsets.fromLTRB(0, 30, 0, 20),
            child: Center(
              child: SelectableText(
                text,
                style: TextStyle(color: textColor, fontSize: 13),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IguanaCoinWithoutTxHistorySupport extends StatelessWidget {
  const _IguanaCoinWithoutTxHistorySupport({Key? key, required this.coin})
    : super(key: key);
  final Coin coin;

  Future<void> _openExplorer(BuildContext context) async {
    final addressesBloc = context.read<CoinAddressesBloc>();
    final addresses = addressesBloc.state.addresses;
    if (addresses.isEmpty) {
      return;
    }

    final PubkeyInfo? selected = addresses.length > 1
        ? await showAddressSearch(
            context,
            addresses: addresses,
            assetNameLabel: coin.abbr,
          )
        : addresses.first;

    if (selected == null || !context.mounted) {
      return;
    }

    final url = getNativeExplorerUrlByCoin(coin, selected.address);
    if (url.isEmpty) {
      return;
    }
    launchURLString(url);
  }

  @override
  Widget build(BuildContext context) {
    final explorerEnabled = context.select<CoinAddressesBloc, bool>((bloc) {
      final addresses = bloc.state.addresses;
      if (addresses.isEmpty) {
        return false;
      }
      return getNativeExplorerUrlByCoin(
        coin,
        addresses.first.address,
      ).isNotEmpty;
    });

    return Column(
      children: [
        Text(LocaleKeys.noTxSupportHidden.tr(), textAlign: TextAlign.center),
        Padding(
          padding: const EdgeInsets.only(top: 10.0),
          child: UiPrimaryButton(
            width: 160,
            height: 30,
            onPressed: explorerEnabled ? () => _openExplorer(context) : null,
            text: LocaleKeys.viewOnExplorer.tr(),
          ),
        ),
      ],
    );
  }
}
