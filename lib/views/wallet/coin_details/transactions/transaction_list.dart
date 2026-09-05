import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/views/wallet/coin_details/transactions/transaction_list_item.dart';

class TransactionList extends StatelessWidget {
  const TransactionList({
    Key? key,
    required this.transactions,
    required this.isInProgress,
    required this.setTransaction,
    required this.coinAbbr,
  }) : super(key: key);
  final List<Transaction> transactions;
  final String coinAbbr;
  final bool isInProgress;
  final void Function(Transaction tx) setTransaction;

  @override
  Widget build(BuildContext context) {
    return transactions.isEmpty
        ? const _EmptyList()
        : _List(
            transactions: transactions,
            isInProgress: isInProgress,
            coinAbbr: coinAbbr,
            setTransaction: setTransaction,
          );
  }
}

class _List extends StatelessWidget {
  const _List({
    required this.transactions,
    required this.isInProgress,
    required this.setTransaction,
    required this.coinAbbr,
  });
  final List<Transaction> transactions;
  final String coinAbbr;
  final bool isInProgress;
  final void Function(Transaction tx) setTransaction;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          if (transactions.isNotEmpty && !isMobile) const HistoryTitle(),
          Padding(
            padding: EdgeInsets.all(isMobile ? 16.0 : 0),
            child: isMobile
                ? HistoryListContent(
                    transactions: transactions,
                    coinAbbr: coinAbbr,
                    setTransaction: setTransaction,
                    isInProgress: isInProgress,
                  )
                : Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    color: Theme.of(context).colorScheme.onSurface,
                    child: HistoryListContent(
                      transactions: transactions,
                      coinAbbr: coinAbbr,
                      setTransaction: setTransaction,
                      isInProgress: isInProgress,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class HistoryListContent extends StatelessWidget {
  const HistoryListContent({
    super.key,
    required this.transactions,
    required this.coinAbbr,
    required this.setTransaction,
    required this.isInProgress,
  });

  final List<Transaction> transactions;
  final String coinAbbr;
  final void Function(Transaction tx) setTransaction;
  final bool isInProgress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (transactions.isNotEmpty && isMobile) const HistoryTitle(),
        if (transactions.isNotEmpty && isMobile) const SizedBox(height: 12),
        ...transactions.asMap().entries.map((entry) {
          final index = entry.key;
          final transaction = entry.value;

          return Column(
            children: [
              TransactionListRow(
                transaction: transaction,
                coinAbbr: coinAbbr,
                setTransaction: setTransaction,
              ),
              if (isMobile && index < transactions.length - 1)
                const SizedBox(height: 12),
            ],
          );
        }).toList(),
        if (isInProgress) const UiSpinnerList(height: 50),
      ],
    );
  }
}

class HistoryTitle extends StatelessWidget {
  const HistoryTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          LocaleKeys.transactions.tr(),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: isMobile ? 16 : 24,
          ),
        ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList();

  @override
  Widget build(BuildContext context) {
    final double verticalPadding = isMobile ? 50 : 70;
    return SliverToBoxAdapter(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: verticalPadding),
          Text(
            LocaleKeys.noTransactionsTitle.tr(),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: isMobile ? 14 : 18,
              color: theme.custom.noTransactionsTextColor,
            ),
          ),
          Text(
            LocaleKeys.noTransactionsDescription.tr(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontSize: isMobile ? 12 : 14,
              color: theme.custom.noTransactionsTextColor,
            ),
          ),
          SizedBox(height: verticalPadding),
        ],
      ),
    );
  }
}
