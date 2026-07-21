part of 'gnosis_card_page.dart';

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.dashboard, required this.state});
  final GnosisCardDashboard dashboard;
  final GnosisCardState state;

  @override
  Widget build(BuildContext context) {
    final foreground = _gnosisAccentForeground(context);
    return Card(
      elevation: 0,
      color: _gnosisAccentSurface(context),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _cardText('dashboard.available'),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: foreground),
            ),
            const SizedBox(height: 6),
            Text(
              _money(context, dashboard.balanceMinor, dashboard.currency),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: foreground,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_cardText('dashboard.pending')}: '
              '${_money(context, dashboard.pendingBalanceMinor, dashboard.currency)}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: foreground),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: foreground,
                    foregroundColor: _gnosisAccentSurface(context),
                  ),
                  onPressed:
                      dashboard.withdrawalAssets.isEmpty ||
                          _cardActionsBlocked(state)
                      ? null
                      : () => _showWithdrawalDialog(context, dashboard),
                  icon: const Icon(Icons.arrow_outward),
                  label: Text(_cardText('dashboard.withdraw')),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: foreground,
                    foregroundColor: _gnosisAccentSurface(context),
                  ),
                  onPressed:
                      dashboard.dailyLimitTarget == null ||
                          dashboard.dailyLimitAsset == null ||
                          _cardActionsBlocked(state)
                      ? null
                      : () => _showLimitDialog(context, dashboard),
                  icon: const Icon(Icons.tune),
                  label: Text(_cardText('dashboard.limit')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.card, required this.state});
  final GnosisPaymentCard card;
  final GnosisCardState state;

  @override
  Widget build(BuildContext context) {
    final frozen = card.status == GnosisCardStatus.frozen;
    final active = card.status == GnosisCardStatus.active;
    final terminal = const {
      GnosisCardStatus.lost,
      GnosisCardStatus.stolen,
      GnosisCardStatus.voided,
    }.contains(card.status);
    final canUseSecureDetails =
        !_cardActionsBlocked(state) && (active || frozen);
    final isMutating = _cardActionsBlocked(state);
    final cardForeground = _gnosisAccentForeground(context);
    final gateway = context.read<GnosisCardDependencies>().secureElement;
    return Semantics(
      label: _cardText(
        'dashboard.cardSemantics',
        args: [card.label, _cardStatus(card.status), card.lastFour],
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 190),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: _gnosisAccentSurface(context)),
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
                        color: cardForeground,
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
                    ).textTheme.titleMedium?.copyWith(color: cardForeground),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '••••  ••••  ••••  ${card.lastFour}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: cardForeground,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: canUseSecureDetails
                        ? () =>
                              gateway.showCardDetails(context, cardId: card.id)
                        : null,
                    icon: const Icon(Icons.visibility_outlined),
                    label: Text(_cardText('dashboard.details')),
                  ),
                  if (card.kind == GnosisCardKind.physical)
                    TextButton.icon(
                      onPressed: canUseSecureDetails
                          ? () => gateway.showPin(context, cardId: card.id)
                          : null,
                      icon: const Icon(Icons.pin_outlined),
                      label: Text(_cardText('dashboard.pin')),
                    ),
                  if (active || frozen)
                    TextButton.icon(
                      onPressed: isMutating
                          ? null
                          : () => context.read<GnosisCardBloc>().add(
                              GnosisCardFreezeChanged(card.id, frozen: !frozen),
                            ),
                      icon: Icon(
                        frozen ? Icons.lock_open : Icons.pause_circle_outline,
                      ),
                      label: Text(
                        frozen
                            ? _cardText('dashboard.unfreeze')
                            : _cardText('dashboard.freeze'),
                      ),
                    ),
                  if (const {
                        GnosisCardStatus.ordered,
                        GnosisCardStatus.shipped,
                      }.contains(card.status) &&
                      card.isActivatable)
                    FilledButton.tonal(
                      onPressed: isMutating
                          ? null
                          : () => context.read<GnosisCardBloc>().add(
                              GnosisCardStatusChanged(
                                card.id,
                                GnosisCardStatus.active,
                              ),
                            ),
                      child: Text(_cardText('dashboard.activate')),
                    ),
                  if (const {
                        GnosisCardStatus.ordered,
                        GnosisCardStatus.shipped,
                      }.contains(card.status) &&
                      !card.isActivatable)
                    TextButton.icon(
                      onPressed: _cardActionsBlocked(state)
                          ? null
                          : () => context.read<GnosisCardBloc>().add(
                              const GnosisSupportOpenRequested(),
                            ),
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: Text(_cardText('dashboard.trackingSupport')),
                    ),
                  if (active || frozen)
                    PopupMenuButton<GnosisCardStatus>(
                      enabled: !isMutating,
                      tooltip: _cardText('dashboard.recoveryActions'),
                      onSelected: (status) async {
                        if (!await _confirmCardStatus(context, status)) return;
                        if (context.mounted) {
                          context.read<GnosisCardBloc>().add(
                            GnosisCardStatusChanged(card.id, status),
                          );
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: GnosisCardStatus.lost,
                          child: Text(_cardText('dashboard.reportLost')),
                        ),
                        PopupMenuItem(
                          value: GnosisCardStatus.stolen,
                          child: Text(_cardText('dashboard.reportStolen')),
                        ),
                        PopupMenuItem(
                          value: GnosisCardStatus.voided,
                          child: Text(_cardText('dashboard.void')),
                        ),
                      ],
                    ),
                  if (terminal)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(_cardStatus(card.status)),
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
  const _ControlsCard({
    required this.cardId,
    required this.cardLabel,
    required this.controls,
    required this.state,
    required this.cardAllowsChanges,
  });
  final String cardId;
  final String cardLabel;
  final GnosisCardControls controls;
  final GnosisCardState state;
  final bool cardAllowsChanges;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _cardText('dashboard.controlsFor', args: [cardLabel]),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          _ControlSwitch(
            label: _cardText('dashboard.contactless'),
            value: controls.contactless,
            onChanged: _enabled
                ? (value) => _set(context, contactless: value)
                : null,
          ),
          _ControlSwitch(
            label: _cardText('dashboard.online'),
            value: controls.online,
            onChanged: _enabled
                ? (value) => _set(context, online: value)
                : null,
          ),
          _ControlSwitch(
            label: _cardText('dashboard.atm'),
            value: controls.atm,
            onChanged: _enabled ? (value) => _set(context, atm: value) : null,
          ),
        ],
      ),
    ),
  );

  bool get _enabled => cardAllowsChanges && !_cardActionsBlocked(state);

  void _set(
    BuildContext context, {
    bool? contactless,
    bool? online,
    bool? atm,
  }) => context.read<GnosisCardBloc>().add(
    GnosisCardControlsChanged(
      cardId,
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
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: value,
    onChanged: onChanged,
  );
}
