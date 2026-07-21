part of 'gnosis_card_page.dart';

class _CardActivity extends StatelessWidget {
  const _CardActivity({required this.dashboard, required this.state});
  final GnosisCardDashboard dashboard;
  final GnosisCardState state;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(
                    dashboard.cards.length > 1
                        ? _cardText('dashboard.activityAllCards')
                        : _cardText('dashboard.activity'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    _cardText(
                      'dashboard.dailyLimitSummary',
                      args: [
                        _money(
                          context,
                          dashboard.dailyLimitMinor,
                          dashboard.currency,
                        ),
                      ],
                    ),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (dashboard.transactions.isEmpty)
                Text(_cardText('dashboard.activityEmpty')),
              for (final transaction in dashboard.transactions)
                _TransactionListItem(transaction: transaction),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(
                    _cardText('dashboard.delayedOperations'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (dashboard.operations.isNotEmpty)
                    TextButton.icon(
                      onPressed: _cardActionsBlocked(state)
                          ? null
                          : () => context.read<GnosisCardBloc>().add(
                              const GnosisDelayedOperationsRefreshRequested(),
                            ),
                      icon: const Icon(Icons.refresh),
                      label: Text(_cardText('dashboard.checkStatus')),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (dashboard.operations.isEmpty)
                Text(_cardText('dashboard.delayedEmpty')),
              for (final operation in dashboard.operations)
                _DelayedOperationListItem(operation: operation),
            ],
          ),
        ),
      ),
    ],
  );
}

class _TransactionListItem extends StatelessWidget {
  const _TransactionListItem({required this.transaction});

  final GnosisCardTransaction transaction;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth < 440 ||
          MediaQuery.textScalerOf(context).scale(1) >= 1.4;
      final amount = Text(
        _money(context, transaction.amountMinor, transaction.currency),
        style: const TextStyle(
          fontFeatures: [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w600,
        ),
      );
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          child: Icon(
            transaction.isDeclined ? Icons.close : Icons.shopping_bag_outlined,
          ),
        ),
        title: Text(transaction.merchant),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              transaction.isDeclined
                  ? '${_formatDate(context, transaction.occurredAt)} · '
                        '${_cardText('dashboard.declined')}'
                  : _formatDate(context, transaction.occurredAt),
            ),
            if (stacked) ...[const SizedBox(height: 4), amount],
          ],
        ),
        trailing: stacked ? null : amount,
      );
    },
  );
}

class _DelayedOperationListItem extends StatelessWidget {
  const _DelayedOperationListItem({required this.operation});

  final DelayedOperation operation;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth < 440 ||
          MediaQuery.textScalerOf(context).scale(1) >= 1.4;
      final status = Chip(label: Text(_operationStatus(operation.status)));
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.schedule_outlined),
        title: Text(_operationTitle(operation.kind)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_operationSubtitle(context, operation)),
            if (stacked) ...[const SizedBox(height: 4), status],
          ],
        ),
        trailing: stacked ? null : status,
      );
    },
  );
}

String _operationSubtitle(BuildContext context, DelayedOperation operation) =>
    switch (operation.status) {
      DelayedOperationStatus.coolingDown => _cardText(
        'dashboard.coolingDown',
        args: [_formatDateTime(context, operation.executableAt)],
      ),
      DelayedOperationStatus.executable => _cardText('dashboard.executable'),
      DelayedOperationStatus.executed => _cardText('dashboard.executed'),
      DelayedOperationStatus.failed => _cardText('dashboard.failed'),
      DelayedOperationStatus.queued => _cardText('dashboard.queued'),
    };

String _operationTitle(DelayedOperationKind kind) => switch (kind) {
  DelayedOperationKind.withdrawal => _cardText('dashboard.withdrawalScheduled'),
  DelayedOperationKind.dailyLimit => _cardText('dashboard.limitScheduled'),
};

class _IntentReview extends StatelessWidget {
  const _IntentReview({
    required this.intent,
    required this.metadata,
    required this.state,
  });
  final PreparedSmartAccountIntent intent;
  final GnosisIntentReviewMetadata metadata;
  final GnosisCardState state;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('gnosis-intent-review'),
    elevation: 0,
    color: Theme.of(context).colorScheme.surface,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _cardText('intent.title'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _ReviewValue(
                label: _cardText('intent.operation'),
                value: intent.kind == SmartAccountIntentKind.withdrawal
                    ? _cardText('intent.withdrawal')
                    : _cardText('intent.dailyLimit'),
              ),
              _ReviewValue(
                label: _cardText('intent.amount'),
                value: _formatAtomicLocalized(
                  context,
                  intent.amount,
                  decimals: metadata.decimals,
                  symbol: metadata.symbol,
                ),
              ),
              if (intent.recipient != null)
                _ReviewValue(
                  label: _cardText('intent.recipient'),
                  value: intent.recipient!,
                ),
              _ReviewValue(
                label: _cardText('intent.assetTarget'),
                value: intent.kind == SmartAccountIntentKind.withdrawal
                    ? metadata.symbol
                    : _cardText('intent.cardSpending'),
              ),
              _ReviewValue(
                label: _cardText('intent.network'),
                value:
                    '${_cardText('dashboard.gnosisNetwork')} · '
                    '${intent.chainId}',
              ),
              if (intent.periodSeconds != null)
                _ReviewValue(
                  label: _cardText('intent.limitPeriod'),
                  value: _cardText(
                    'intent.hours',
                    args: [
                      '${Duration(seconds: intent.periodSeconds!).inHours}',
                    ],
                  ),
                ),
              _ReviewValue(
                label: _cardText('intent.delay'),
                value: _cardText('intent.providerDelay'),
              ),
              _ReviewValue(
                label: _cardText('intent.fee'),
                value: metadata.feeMinor != null && metadata.feeCurrency != null
                    ? _money(context, metadata.feeMinor!, metadata.feeCurrency!)
                    : _cardText('intent.feeInWallet'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            metadata.feeMinor != null && metadata.feeCurrency != null
                ? _cardText('intent.warningWithFee')
                : _cardText('intent.warningWithoutFee'),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: _cardActionsBlocked(state)
                    ? null
                    : () => context.read<GnosisCardBloc>().add(
                        const GnosisPreparedIntentCancelled(),
                      ),
                child: Text(_cardText('forms.cancel')),
              ),
              FilledButton.icon(
                onPressed: _cardActionsBlocked(state)
                    ? null
                    : () => context.read<GnosisCardBloc>().add(
                        const GnosisPreparedIntentConfirmed(),
                      ),
                icon: const Icon(Icons.draw_outlined),
                label: Text(_cardText('intent.approve')),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ReviewValue extends StatelessWidget {
  const _ReviewValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        SelectableText(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stack =
            constraints.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.4;
        final valueWidget = SelectableText(
          value,
          textAlign: stack ? TextAlign.start : TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w600),
        );
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Text(label), const SizedBox(height: 2), valueWidget],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Expanded(child: valueWidget),
          ],
        );
      },
    ),
  );
}
