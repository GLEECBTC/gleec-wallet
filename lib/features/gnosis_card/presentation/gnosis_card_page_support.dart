part of 'gnosis_card_page.dart';

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final GnosisCardStatus status;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF2D2538) : const Color(0xFFF2ECFA);
    final foreground = dark ? const Color(0xFFF8F4FC) : const Color(0xFF2E2140);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: foreground),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          _cardStatus(status),
          style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _RecoveryState extends StatelessWidget {
  const _RecoveryState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          children: [
            Icon(icon, size: 52),
            const SizedBox(height: 20),
            Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            if (onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    ),
  );
}

class _PrivacyShield extends StatelessWidget {
  const _PrivacyShield();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          label: _cardText('privacy.hidden'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.visibility_off_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                _cardText('privacy.hidden'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _showWithdrawalDialog(
  BuildContext context,
  GnosisCardDashboard dashboard,
) async {
  if (dashboard.withdrawalAssets.isEmpty) return;
  final formKey = GlobalKey<FormState>();
  final recipient = TextEditingController();
  final amount = TextEditingController();
  var selectedAsset = dashboard.withdrawalAssets.first;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(_cardText('forms.withdrawTitle')),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<GnosisCardAsset>(
                    initialValue: selectedAsset,
                    decoration: InputDecoration(
                      labelText: _cardText('forms.asset'),
                    ),
                    items: [
                      for (final asset in dashboard.withdrawalAssets)
                        DropdownMenuItem(
                          value: asset,
                          child: Text(asset.symbol),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedAsset = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: recipient,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: _cardText('forms.recipient'),
                    ),
                    validator: (value) =>
                        RegExp(
                          r'^0x[a-fA-F0-9]{40}$',
                        ).hasMatch(value?.trim() ?? '')
                        ? null
                        : _cardText('forms.recipientRequired'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          '${_cardText('forms.amount')} (${selectedAsset.symbol})',
                    ),
                    validator: (value) =>
                        _parseDecimalAtomic(
                              value ?? '',
                              selectedAsset.decimals,
                            ) ==
                            null
                        ? _cardText('forms.amountRequired')
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _InfoRow(
                    label: _cardText('forms.network'),
                    value:
                        '${_cardText('dashboard.gnosisNetwork')} · '
                        '${selectedAsset.chainId}',
                  ),
                  _InfoRow(
                    label: _cardText('forms.fee'),
                    value: _cardText('forms.feeAtReview'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_cardText('forms.cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: Text(_cardText('forms.review')),
          ),
        ],
      ),
    ),
  );
  if (accepted == true && context.mounted) {
    final atomic = _parseDecimalAtomic(amount.text, selectedAsset.decimals);
    if (atomic != null) {
      context.read<GnosisCardBloc>().add(
        GnosisWithdrawalReviewRequested(
          WithdrawalRequest(
            assetContract: selectedAsset.contractAddress,
            assetSymbol: selectedAsset.symbol,
            recipient: recipient.text.trim(),
            amountAtomic: atomic,
            decimals: selectedAsset.decimals,
          ),
        ),
      );
    }
  }
  recipient.dispose();
  amount.dispose();
}

Future<void> _showLimitDialog(
  BuildContext context,
  GnosisCardDashboard dashboard,
) async {
  final target = dashboard.dailyLimitTarget;
  final asset = dashboard.dailyLimitAsset;
  if (target == null || asset == null) return;
  final formKey = GlobalKey<FormState>();
  final amount = TextEditingController();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(_cardText('forms.limitTitle')),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_cardText('forms.limitBody')),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        '${_cardText('forms.limitAmount')} (${asset.symbol})',
                  ),
                  validator: (value) =>
                      _parseDecimalAtomic(value ?? '', asset.decimals) == null
                      ? _cardText('forms.amountRequired')
                      : null,
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  label: _cardText('forms.network'),
                  value:
                      '${_cardText('dashboard.gnosisNetwork')} · '
                      '${asset.chainId}',
                ),
                _InfoRow(
                  label: _cardText('forms.fee'),
                  value: _cardText('forms.feeAtReview'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(_cardText('forms.cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.pop(dialogContext, true);
            }
          },
          child: Text(_cardText('forms.review')),
        ),
      ],
    ),
  );
  if (accepted == true && context.mounted) {
    final atomic = _parseDecimalAtomic(amount.text, asset.decimals);
    if (atomic != null) {
      context.read<GnosisCardBloc>().add(
        GnosisDailyLimitReviewRequested(
          DailyLimitRequest(
            bouncer: target,
            amountAtomic: atomic,
            decimals: asset.decimals,
          ),
        ),
      );
    }
  }
  amount.dispose();
}

String _money(BuildContext context, int minor, String currency) =>
    NumberFormat.simpleCurrency(
      name: currency,
      locale: context.locale.toString(),
    ).format(minor / 100);

String _cardText(String key, {List<String>? args}) =>
    'gnosisCard.$key'.tr(args: args);

String _formatDate(BuildContext context, DateTime value) =>
    DateFormat.yMMMd(context.locale.toString()).format(value.toLocal());

String _formatDateTime(BuildContext context, DateTime value) =>
    DateFormat.yMMMd(
      context.locale.toString(),
    ).add_jm().format(value.toLocal());

String _cardStatus(GnosisCardStatus status) => _cardText(
  'dashboard.${switch (status) {
    GnosisCardStatus.ordered => 'statusOrdered',
    GnosisCardStatus.shipped => 'statusShipped',
    GnosisCardStatus.active => 'statusActive',
    GnosisCardStatus.frozen => 'statusFrozen',
    GnosisCardStatus.lost => 'statusLost',
    GnosisCardStatus.stolen => 'statusStolen',
    GnosisCardStatus.voided => 'statusVoided',
  }}',
);

String _physicalOrderStatus(PhysicalCardOrderStatus status) => _cardText(
  'dashboard.${switch (status) {
    PhysicalCardOrderStatus.pendingTransaction => 'orderPendingTransaction',
    PhysicalCardOrderStatus.transactionComplete => 'orderTransactionComplete',
    PhysicalCardOrderStatus.confirmationRequired => 'orderConfirmationRequired',
    PhysicalCardOrderStatus.ready => 'orderReady',
    PhysicalCardOrderStatus.cardCreated => 'orderCardCreated',
    PhysicalCardOrderStatus.failedTransaction => 'orderFailedTransaction',
    PhysicalCardOrderStatus.cancelled => 'orderCancelled',
  }}',
);

String _operationStatus(DelayedOperationStatus status) => _cardText(
  'dashboard.${switch (status) {
    DelayedOperationStatus.queued => 'operationQueued',
    DelayedOperationStatus.coolingDown => 'operationCoolingDown',
    DelayedOperationStatus.executable => 'operationExecutable',
    DelayedOperationStatus.executed => 'operationExecuted',
    DelayedOperationStatus.failed => 'operationFailed',
  }}',
);

bool _cardActionsBlocked(GnosisCardState state) =>
    state.failure != null ||
    state.busyActions.isNotEmpty ||
    state.snapshot?.safeMigration.isActive == true ||
    state.snapshot?.safeMigration.status == GnosisSafeMigrationStatus.failed ||
    _migrationConfigurationMismatch(state.snapshot);

bool _migrationConfigurationMismatch(GnosisCardSnapshot? snapshot) {
  if (snapshot?.safeMigration.status != GnosisSafeMigrationStatus.completed) {
    return false;
  }
  final currentSafe = snapshot?.safeMigration.currentSafe;
  final configuration = snapshot?.safeConfiguration;
  return currentSafe == null ||
      configuration == null ||
      configuration.safeAddress?.toLowerCase() !=
          currentSafe.address.toLowerCase();
}

String _dashboardBusyMessage(Set<GnosisCardAction> actions) {
  if (actions.contains(GnosisCardAction.confirmPreparedIntent)) {
    return _cardText('dashboard.authorizingChange');
  }
  if (actions.contains(GnosisCardAction.refreshDelayedOperations) ||
      actions.contains(GnosisCardAction.initialize)) {
    return _cardText('dashboard.refreshing');
  }
  return _cardText('dashboard.updatingCard');
}

String? _dashboardSuccessMessage(GnosisCardAction? action) => switch (action) {
  GnosisCardAction.confirmPreparedIntent => _cardText(
    'dashboard.scheduledSuccess',
  ),
  GnosisCardAction.prepareWithdrawal ||
  GnosisCardAction.prepareDailyLimit => _cardText('dashboard.reviewReady'),
  GnosisCardAction.setCardFrozen ||
  GnosisCardAction.setCardStatus ||
  GnosisCardAction.updateCardControls => _cardText(
    'dashboard.cardUpdateSuccess',
  ),
  GnosisCardAction.refreshDelayedOperations => _cardText(
    'dashboard.statusRefreshed',
  ),
  _ => null,
};

Color _gnosisAccentSurface(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF33234A)
    : const Color(0xFFEDE2FF);

Color _gnosisAccentForeground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFFFFFF)
    : const Color(0xFF28183D);

BigInt? _parseDecimalAtomic(String input, int decimals) {
  final normalized = input.trim().replaceAll(',', '.');
  final pattern = decimals == 0
      ? RegExp(r'^\d+$')
      : RegExp('^\\d+(?:\\.\\d{1,$decimals})?\$');
  if (!pattern.hasMatch(normalized)) {
    return null;
  }
  final parts = normalized.split('.');
  final whole = parts.first;
  final fraction = parts.length == 1 ? '' : parts.last;
  final atomic = BigInt.tryParse('$whole${fraction.padRight(decimals, '0')}');
  return atomic == null || atomic <= BigInt.zero ? null : atomic;
}

String _formatAtomicLocalized(
  BuildContext context,
  BigInt amount, {
  required int decimals,
  required String symbol,
}) {
  final negative = amount.isNegative;
  final digits = amount.abs().toString().padLeft(decimals + 1, '0');
  final whole = digits.substring(0, digits.length - decimals);
  final fraction = digits
      .substring(digits.length - decimals)
      .replaceFirst(RegExp(r'0+$'), '');
  final format = NumberFormat.decimalPattern(context.locale.toString());
  final groupedWhole = format.format(BigInt.parse(whole));
  final separator = format.symbols.DECIMAL_SEP;
  return '${negative ? '−' : ''}$groupedWhole'
      '${fraction.isEmpty ? '' : '$separator$fraction'} '
      '$symbol';
}

String _short(String value) => value.length <= 16
    ? value
    : '${value.substring(0, 8)}…${value.substring(value.length - 6)}';

Future<bool> _confirmCardStatus(
  BuildContext context,
  GnosisCardStatus status,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(switch (status) {
          GnosisCardStatus.lost => _cardText('confirmation.lostTitle'),
          GnosisCardStatus.stolen => _cardText('confirmation.stolenTitle'),
          _ => _cardText('confirmation.voidTitle'),
        }),
        content: Text(_cardText('confirmation.terminalBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_cardText('confirmation.keep')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_cardText('confirmation.confirm')),
          ),
        ],
      ),
    ) ??
    false;
