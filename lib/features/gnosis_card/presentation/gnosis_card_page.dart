import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_bloc.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_dependencies.dart';

class GnosisCardPage extends StatelessWidget {
  const GnosisCardPage({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<GnosisCardBloc, GnosisCardState>(
        builder: (context, state) {
          if (state.status == GnosisCardLoadStatus.disabled) {
            return _RecoveryState(
              icon: Icons.credit_card_off_outlined,
              title: 'Cards are unavailable',
              message: state.message ?? 'This feature is disabled.',
            );
          }
          if (state.status == GnosisCardLoadStatus.failure) {
            return _RecoveryState(
              icon: Icons.cloud_off_outlined,
              title: 'We could not continue',
              message: state.message ?? 'Try again.',
              actionLabel: 'Retry safely',
              onAction: () =>
                  context.read<GnosisCardBloc>().add(const GnosisCardStarted()),
            );
          }
          final snapshot = state.snapshot;
          return Stack(
            children: [
              if (snapshot == null)
                const Center(child: CircularProgressIndicator())
              else if (snapshot.stage != GnosisOnboardingStage.ready)
                _Onboarding(snapshot: snapshot)
              else
                _Dashboard(snapshot: snapshot),
              if (state.status == GnosisCardLoadStatus.loading)
                const Positioned.fill(child: _LoadingScrim()),
            ],
          );
        },
      );
}

class _Onboarding extends StatelessWidget {
  const _Onboarding({required this.snapshot});
  final GnosisCardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final content = _stageContent(snapshot.stage);
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Card', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'A secure card account connected to your wallet.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Progress(stage: snapshot.stage),
                      const SizedBox(height: 32),
                      Icon(content.icon, size: 40, color: colorScheme.primary),
                      const SizedBox(height: 20),
                      Text(
                        content.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(content.description),
                      if (snapshot.deployment != null) ...[
                        const SizedBox(height: 20),
                        _InfoRow(
                          label: 'Deployment',
                          value: snapshot.deployment!.status.name,
                        ),
                      ],
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        onPressed: () => context.read<GnosisCardBloc>().add(
                          const GnosisCardAdvanceRequested(),
                        ),
                        icon: Icon(content.icon),
                        label: Text(content.action),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Safe deployment and setup are performed by the Gnosis Pay API. '
                'The wallet registers the returned Safe with KDF only after deployment succeeds.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.snapshot});
  final GnosisCardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final dashboard = snapshot.dashboard!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DashboardHeader(dashboard: dashboard),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final overview = _CardOverview(
                    dashboard: dashboard,
                    deployment: snapshot.deployment,
                  );
                  final activity = _CardActivity(dashboard: dashboard);
                  if (constraints.maxWidth >= 900) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 410, child: overview),
                        const SizedBox(width: 24),
                        Expanded(child: activity),
                      ],
                    );
                  }
                  return Column(
                    children: [overview, const SizedBox(height: 24), activity],
                  );
                },
              ),
              if (snapshot.reviewIntent != null) ...[
                const SizedBox(height: 24),
                _IntentReview(intent: snapshot.reviewIntent!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CardOverview extends StatelessWidget {
  const _CardOverview({required this.dashboard, required this.deployment});
  final GnosisCardDashboard dashboard;
  final SafeDeployment? deployment;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _BalanceCard(dashboard: dashboard),
      const SizedBox(height: 16),
      for (final card in dashboard.cards) ...[
        _PaymentCard(card: card),
        const SizedBox(height: 16),
      ],
      _ControlsCard(controls: dashboard.controls),
      const SizedBox(height: 16),
      Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Smart account',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _InfoRow(
                label: 'Safe',
                value: _short(deployment?.safeAddress ?? 'Not registered'),
              ),
              const _InfoRow(label: 'Network', value: 'Gnosis Chain · 100'),
              _InfoRow(
                label: 'Delay',
                value: _short(deployment?.delayModule ?? 'Not registered'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.dashboard});
  final GnosisCardDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Card', style: Theme.of(context).textTheme.headlineMedium),
        Text(
          'Your spending account and controls',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
    final order = OutlinedButton.icon(
      onPressed: dashboard.physicalOrder == null
          ? () async {
              if (await _confirmPhysicalOrder(context) && context.mounted) {
                context.read<GnosisCardBloc>().add(
                  const GnosisPhysicalCardRequested(),
                );
              }
            }
          : null,
      icon: const Icon(Icons.local_shipping_outlined),
      label: Text(
        dashboard.physicalOrder == null
            ? 'Order physical card'
            : dashboard.physicalOrder!.status.name,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.4) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 16), order],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            order,
          ],
        );
      },
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.dashboard});
  final GnosisCardDashboard dashboard;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available to spend',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          Text(
            _money(dashboard.balanceMinor, dashboard.currency),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _showWithdrawalDialog(context),
                  icon: const Icon(Icons.arrow_outward),
                  label: const Text('Withdraw'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _showLimitDialog(context),
                  icon: const Icon(Icons.tune),
                  label: const Text('Limit'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.card});
  final GnosisPaymentCard card;

  @override
  Widget build(BuildContext context) {
    final frozen = card.status == GnosisCardStatus.frozen;
    final scheme = Theme.of(context).colorScheme;
    final gateway = context.read<GnosisCardDependencies>().secureElement;
    return Semantics(
      label:
          '${card.kind.name} card ending ${card.lastFour}, ${card.status.name}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 190),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, scheme.tertiary],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        card.kind == GnosisCardKind.virtual
                            ? Icons.language
                            : Icons.contactless,
                        color: scheme.onPrimary,
                      ),
                      const Spacer(),
                      _StatusPill(status: card.status),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    card.label,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: scheme.onPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '••••  ••••  ••••  ${card.lastFour}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: scheme.onPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () =>
                          gateway.showCardDetails(context, cardId: card.id),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Details'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: card.kind == GnosisCardKind.physical
                          ? () => gateway.showPin(context, cardId: card.id)
                          : null,
                      icon: const Icon(Icons.pin_outlined),
                      label: const Text('PIN'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed:
                          card.status == GnosisCardStatus.active || frozen
                          ? () => context.read<GnosisCardBloc>().add(
                              GnosisCardFreezeChanged(card.id, frozen: !frozen),
                            )
                          : null,
                      icon: Icon(frozen ? Icons.lock_open : Icons.ac_unit),
                      label: Text(frozen ? 'Unfreeze' : 'Freeze'),
                    ),
                  ),
                  PopupMenuButton<GnosisCardStatus>(
                    tooltip: 'Card recovery actions',
                    onSelected: (status) async {
                      if (status != GnosisCardStatus.active &&
                          !await _confirmCardStatus(context, status)) {
                        return;
                      }
                      if (context.mounted) {
                        context.read<GnosisCardBloc>().add(
                          GnosisCardStatusChanged(card.id, status),
                        );
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: GnosisCardStatus.active,
                        child: Text('Activate'),
                      ),
                      PopupMenuItem(
                        value: GnosisCardStatus.lost,
                        child: Text('Mark lost'),
                      ),
                      PopupMenuItem(
                        value: GnosisCardStatus.stolen,
                        child: Text('Mark stolen'),
                      ),
                      PopupMenuItem(
                        value: GnosisCardStatus.voided,
                        child: Text('Void card'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlsCard extends StatelessWidget {
  const _ControlsCard({required this.controls});
  final GnosisCardControls controls;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Card controls', style: Theme.of(context).textTheme.titleMedium),
          _ControlSwitch(
            label: 'Contactless',
            value: controls.contactless,
            onChanged: (value) => _set(context, contactless: value),
          ),
          _ControlSwitch(
            label: 'Online payments',
            value: controls.online,
            onChanged: (value) => _set(context, online: value),
          ),
          _ControlSwitch(
            label: 'ATM withdrawals',
            value: controls.atm,
            onChanged: (value) => _set(context, atm: value),
          ),
        ],
      ),
    ),
  );

  void _set(
    BuildContext context, {
    bool? contactless,
    bool? online,
    bool? atm,
  }) => context.read<GnosisCardBloc>().add(
    GnosisCardControlsChanged(
      controls.copyWith(contactless: contactless, online: online, atm: atm),
    ),
  );
}

class _ControlSwitch extends StatelessWidget {
  const _ControlSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: value,
    onChanged: onChanged,
  );
}

class _CardActivity extends StatelessWidget {
  const _CardActivity({required this.dashboard});
  final GnosisCardDashboard dashboard;

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
                    'Recent activity',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    'Daily limit ${_money(dashboard.dailyLimitMinor, dashboard.currency)}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final transaction in dashboard.transactions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Icon(
                      transaction.isDeclined
                          ? Icons.close
                          : Icons.shopping_bag_outlined,
                    ),
                  ),
                  title: Text(transaction.merchant),
                  subtitle: Text(
                    '${transaction.occurredAt.day}/${transaction.occurredAt.month}/${transaction.occurredAt.year}',
                  ),
                  trailing: Text(
                    _money(transaction.amountMinor, transaction.currency),
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
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
                    'Delayed operations',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (dashboard.operations.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => context.read<GnosisCardBloc>().add(
                        const GnosisDelayedOperationsRefreshRequested(),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Check status'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (dashboard.operations.isEmpty)
                const Text('No withdrawals or limit changes are queued.'),
              for (final operation in dashboard.operations)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: Text(operation.summary),
                  subtitle: Text(_operationSubtitle(operation)),
                  trailing: Chip(label: Text(operation.status.name)),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

String _operationSubtitle(
  DelayedOperation operation,
) => switch (operation.status) {
  DelayedOperationStatus.coolingDown =>
    'Temporary freeze until ${operation.executableAt.hour.toString().padLeft(2, '0')}:${operation.executableAt.minute.toString().padLeft(2, '0')}',
  DelayedOperationStatus.executable =>
    'Cooldown complete. The operation is ready to execute.',
  DelayedOperationStatus.executed => 'Executed successfully.',
  DelayedOperationStatus.failed => 'Execution failed. Review recovery options.',
  DelayedOperationStatus.queued => 'Queued for the delay module.',
};

class _IntentReview extends StatelessWidget {
  const _IntentReview({required this.intent});
  final PreparedSmartAccountIntent intent;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('gnosis-intent-review'),
    elevation: 0,
    color: Theme.of(context).colorScheme.secondaryContainer,
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
                  'Review before signing',
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
              _ReviewValue(label: 'Operation', value: intent.kind.name),
              _ReviewValue(label: 'Amount / limit', value: '${intent.amount}'),
              _ReviewValue(
                label: 'Recipient',
                value: _short(intent.recipient ?? '—'),
              ),
              _ReviewValue(
                label: 'Asset / target',
                value: _short(intent.target),
              ),
              _ReviewValue(label: 'Safe', value: _short(intent.safeAddress)),
              _ReviewValue(label: 'Network', value: '${intent.chainId}'),
              _ReviewValue(label: 'Delay', value: _short(intent.delayModule)),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Submitting this signature queues a delayed operation. Card spending may be temporarily frozen during the cooldown.',
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => context.read<GnosisCardBloc>().add(
                  const GnosisPreparedIntentCancelled(),
                ),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => context.read<GnosisCardBloc>().add(
                  const GnosisPreparedIntentConfirmed(),
                ),
                icon: const Icon(Icons.draw_outlined),
                label: const Text('Sign with KDF'),
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
    width: 180,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.stage});
  final GnosisOnboardingStage stage;

  @override
  Widget build(BuildContext context) {
    final progress = (stage.index + 1) / GnosisOnboardingStage.values.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Setup ${stage.index + 1} of 7'),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: progress.clamp(0, 1).toDouble()),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final GnosisCardStatus status;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        status.name,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _LoadingScrim extends StatelessWidget {
  const _LoadingScrim();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
    child: const Center(child: CircularProgressIndicator()),
  );
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
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
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

class _StageContent {
  const _StageContent(this.title, this.description, this.action, this.icon);
  final String title;
  final String description;
  final String action;
  final IconData icon;
}

_StageContent _stageContent(GnosisOnboardingStage stage) => switch (stage) {
  GnosisOnboardingStage.signedOut => const _StageContent(
    'Connect your wallet',
    'KDF signs a SIWE message using EIP-191. This proves address ownership without sending a transaction.',
    'Sign in securely',
    Icons.key_outlined,
  ),
  GnosisOnboardingStage.terms => const _StageContent(
    'Review the terms',
    'Read and accept the card programme terms before registration.',
    'Accept and continue',
    Icons.description_outlined,
  ),
  GnosisOnboardingStage.registration => const _StageContent(
    'Create your card profile',
    'Confirm the identity details used for card eligibility.',
    'Create profile',
    Icons.person_outline,
  ),
  GnosisOnboardingStage.phoneAndSourceOfFunds => const _StageContent(
    'Contact and funding details',
    'Verify a phone number and describe the source of funds for compliance.',
    'Submit details',
    Icons.fact_check_outlined,
  ),
  GnosisOnboardingStage.kycPending => const _StageContent(
    'Identity verification',
    'The deterministic adapter is waiting for the mocked KYC decision.',
    'Check status',
    Icons.badge_outlined,
  ),
  GnosisOnboardingStage.safeDeployment => const _StageContent(
    'Deploy the card Safe',
    'The mock Gnosis API models accepted, processing, and final deployment states. The wallet does not deploy the Safe.',
    'Deploy via API',
    Icons.account_balance_wallet_outlined,
  ),
  GnosisOnboardingStage.cardIssuance => const _StageContent(
    'Create a virtual card',
    'Issue the first card after the API-owned Safe passes integrity checks and KDF registration.',
    'Create virtual card',
    Icons.credit_card,
  ),
  GnosisOnboardingStage.ready => const _StageContent(
    'Ready',
    'Your card is ready.',
    'Open card',
    Icons.check_circle_outline,
  ),
};

Future<void> _showWithdrawalDialog(BuildContext context) async {
  final recipient = TextEditingController(
    text: '0x4444444444444444444444444444444444444444',
  );
  final amount = TextEditingController(text: '1000000');
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Prepare withdrawal'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: recipient,
              decoration: const InputDecoration(labelText: 'Recipient'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Atomic amount',
                helperText: 'Mock USDC uses 6 decimal places',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Review'),
        ),
      ],
    ),
  );
  if (accepted == true && context.mounted) {
    final atomic = BigInt.tryParse(amount.text);
    if (atomic != null && atomic > BigInt.zero) {
      context.read<GnosisCardBloc>().add(
        GnosisWithdrawalReviewRequested(
          WithdrawalRequest(
            assetContract: '0x3333333333333333333333333333333333333333',
            assetSymbol: 'USDC',
            recipient: recipient.text.trim(),
            amountAtomic: atomic,
            decimals: 6,
          ),
        ),
      );
    }
  }
  recipient.dispose();
  amount.dispose();
}

Future<void> _showLimitDialog(BuildContext context) async {
  final amount = TextEditingController(text: '250000000');
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Change daily limit'),
      content: TextField(
        controller: amount,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Atomic daily limit',
          helperText:
              'The change is delayed and may temporarily freeze spending',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Review'),
        ),
      ],
    ),
  );
  if (accepted == true && context.mounted) {
    final atomic = BigInt.tryParse(amount.text);
    if (atomic != null && atomic > BigInt.zero) {
      context.read<GnosisCardBloc>().add(
        GnosisDailyLimitReviewRequested(
          DailyLimitRequest(
            bouncer: '0x5555555555555555555555555555555555555555',
            amountAtomic: atomic,
            decimals: 6,
          ),
        ),
      );
    }
  }
  amount.dispose();
}

String _money(int minor, String currency) {
  final value = minor.abs() / 100;
  final sign = minor < 0 ? '−' : '';
  return '$sign$currency ${value.toStringAsFixed(2)}';
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
        title: Text(
          status == GnosisCardStatus.voided
              ? 'Void this card?'
              : 'Mark card as ${status.name}?',
        ),
        content: Text(
          status == GnosisCardStatus.voided
              ? 'Voiding is permanent. You will need to issue a replacement card.'
              : 'Payments will stop immediately. You can use the recovery actions to replace or reactivate the card.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep card'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              status == GnosisCardStatus.voided ? 'Void card' : 'Confirm',
            ),
          ),
        ],
      ),
    ) ??
    false;

Future<bool> _confirmPhysicalOrder(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Order a physical card'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mock delivery address\n12 Example Street\nCape Town'),
            SizedBox(height: 16),
            _InfoRow(label: 'Card and delivery', value: 'EUR 9.99'),
            _InfoRow(label: 'Estimated arrival', value: '3–5 days'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pay and order'),
          ),
        ],
      ),
    ) ??
    false;
