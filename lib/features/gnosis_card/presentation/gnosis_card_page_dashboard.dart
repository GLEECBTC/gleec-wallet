part of 'gnosis_card_page.dart';

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.snapshot,
    required this.state,
    required this.showMigrationNotice,
    required this.onDismissMigration,
  });
  final GnosisCardSnapshot snapshot;
  final GnosisCardState state;
  final bool showMigrationNotice;
  final VoidCallback onDismissMigration;

  @override
  Widget build(BuildContext context) {
    final dashboard = snapshot.dashboard!;
    final successMessage = _dashboardSuccessMessage(state.lastCompletedAction);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (snapshot.safeMigration.isActive) ...[
                GnosisStatusBanner(
                  title: _cardText('migration.processingTitle'),
                  message: _cardText('migration.processingBody'),
                  icon: Icons.sync,
                  isLiveRegion: true,
                ),
                const SizedBox(height: 16),
              ],
              if (showMigrationNotice) ...[
                Card(
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.shield_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _cardText('migration.title'),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(_cardText('migration.body')),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: onDismissMigration,
                          tooltip: _cardText('migration.dismiss'),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (state.busyActions.isNotEmpty) ...[
                Semantics(
                  liveRegion: true,
                  label: _dashboardBusyMessage(state.busyActions),
                  child: Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (MediaQuery.disableAnimationsOf(context))
                            Container(
                              height: 4,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          else
                            const LinearProgressIndicator(),
                          const SizedBox(height: 10),
                          Text(_dashboardBusyMessage(state.busyActions)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (state.failure != null) ...[
                GnosisServerErrorBanner(
                  message: gnosisLocalizedFailureMessage(state.failure!),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: state.busyActions.isNotEmpty
                        ? null
                        : () => context.read<GnosisCardBloc>().add(
                            state.intervention ==
                                    GnosisCardIntervention.contactSupport
                                ? const GnosisSupportOpenRequested()
                                : const GnosisCardResumed(),
                          ),
                    icon: Icon(
                      state.intervention ==
                              GnosisCardIntervention.contactSupport
                          ? Icons.support_agent
                          : Icons.refresh,
                    ),
                    label: Text(
                      state.intervention ==
                              GnosisCardIntervention.contactSupport
                          ? LocaleKeys.gnosisCard_openSupport.tr()
                          : _cardText('dashboard.reconnect'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (successMessage != null && state.failure == null) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    successMessage,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (snapshot.progress.isPinProvisioned) ...[
                GnosisStatusBanner(
                  title: LocaleKeys.gnosisCard_order_completeTitle.tr(),
                  message: LocaleKeys.gnosisCard_order_completeBody.tr(),
                  icon: Icons.local_shipping_outlined,
                ),
                const SizedBox(height: 20),
              ] else if (snapshot.progress.cards.any(
                (card) => card.kind == GnosisCardKind.virtual,
              )) ...[
                GnosisStatusBanner(
                  title: LocaleKeys.gnosisCard_virtual_completeTitle.tr(),
                  message: LocaleKeys.gnosisCard_virtual_completeBody.tr(),
                  icon: Icons.check_circle_outline,
                ),
                const SizedBox(height: 20),
              ],
              _DashboardHeader(snapshot: snapshot, state: state),
              if (state.lastUpdatedAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  _cardText(
                    'dashboard.lastUpdated',
                    args: [_formatDateTime(context, state.lastUpdatedAt!)],
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 24),
              if (snapshot.reviewIntent != null &&
                  snapshot.reviewMetadata != null) ...[
                Semantics(
                  liveRegion: true,
                  container: true,
                  label: _cardText('intent.reviewReady'),
                  child: _IntentReview(
                    intent: snapshot.reviewIntent!,
                    metadata: snapshot.reviewMetadata!,
                    state: state,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final overview = _CardOverview(
                    dashboard: dashboard,
                    configuration: snapshot.safeConfiguration,
                    state: state,
                  );
                  final activity = _CardActivity(
                    dashboard: dashboard,
                    state: state,
                  );
                  if (constraints.maxWidth >= 900 &&
                      MediaQuery.textScalerOf(context).scale(1) < 1.4) {
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
            ],
          ),
        ),
      ),
    );
  }
}

class _CardOverview extends StatefulWidget {
  const _CardOverview({
    required this.dashboard,
    required this.configuration,
    required this.state,
  });
  final GnosisCardDashboard dashboard;
  final SafeConfiguration? configuration;
  final GnosisCardState state;

  @override
  State<_CardOverview> createState() => _CardOverviewState();
}

class _CardOverviewState extends State<_CardOverview> {
  String? _selectedCardId;

  GnosisPaymentCard get _selectedCard {
    final cards = widget.dashboard.cards;
    return cards.firstWhere(
      (card) => card.id == _selectedCardId,
      orElse: () => cards.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = widget.dashboard;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BalanceCard(dashboard: dashboard, state: widget.state),
        const SizedBox(height: 16),
        if (dashboard.cards.length > 1) ...[
          DropdownButtonFormField<String>(
            initialValue: _selectedCard.id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _cardText('dashboard.selectedCard'),
            ),
            items: [
              for (final card in dashboard.cards)
                DropdownMenuItem(
                  value: card.id,
                  child: Text(
                    '${card.label} · •••• ${card.lastFour}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _selectedCardId = value),
          ),
          const SizedBox(height: 16),
        ],
        _PaymentCard(card: _selectedCard, state: widget.state),
        const SizedBox(height: 16),
        _ControlsCard(
          cardId: _selectedCard.id,
          cardLabel: _selectedCard.label,
          controls: _selectedCard.controls,
          state: widget.state,
          cardAllowsChanges: const {
            GnosisCardStatus.active,
            GnosisCardStatus.frozen,
          }.contains(_selectedCard.status),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          child: ExpansionTile(
            title: Text(_cardText('dashboard.accountDetails')),
            subtitle: Text(_cardText('dashboard.technicalDetails')),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _InfoRow(
                label: _cardText('dashboard.safe'),
                value: _short(
                  widget.configuration?.safeAddress ??
                      LocaleKeys.gnosisCard_safe_notRegistered.tr(),
                ),
              ),
              _InfoRow(
                label: _cardText('dashboard.network'),
                value: '${_cardText('dashboard.gnosisNetwork')} · 100',
              ),
              _InfoRow(
                label: _cardText('dashboard.delay'),
                value: _short(
                  widget.configuration?.delayModule ??
                      LocaleKeys.gnosisCard_safe_notRegistered.tr(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.snapshot, required this.state});
  final GnosisCardSnapshot snapshot;
  final GnosisCardState state;

  @override
  Widget build(BuildContext context) {
    final dashboard = snapshot.dashboard!;
    GnosisCardProduct? physicalProduct;
    for (final product in snapshot.cardProducts) {
      if (product.kind == GnosisCardKind.physical) {
        physicalProduct = product;
        break;
      }
    }
    final physicalProductId = physicalProduct?.id;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            _cardText('dashboard.title'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Text(
          _cardText('dashboard.subtitle'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
    final order = OutlinedButton.icon(
      onPressed:
          dashboard.physicalOrder == null &&
              physicalProductId != null &&
              !_cardActionsBlocked(state)
          ? () => context.read<GnosisCardBloc>().add(
              GnosisCardProductSelected(physicalProductId),
            )
          : null,
      icon: const Icon(Icons.local_shipping_outlined),
      label: Text(
        dashboard.physicalOrder == null
            ? _cardText('dashboard.orderPhysical')
            : _physicalOrderStatus(dashboard.physicalOrder!.status),
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
