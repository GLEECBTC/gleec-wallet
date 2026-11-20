part of 'swap_execution_view.dart';

extension _ExecutionSections on _ExecutionBodyState {
  /// Controls remain immediately available while the status icon settles.
  Widget _arrive(Widget child, {required bool live, int order = 0}) => child;

  List<Widget> _running(
    BuildContext context,
    SwapExecutionState state,
    SwapExecutionSnapshot snapshot,
    SwapExecutionDisplay copy,
  ) {
    final cancelMessage = switch (state.cancelStatus) {
      SwapCancelStatus.refusedAlreadySent =>
        LocaleKeys.swapCancelRefusedSent.tr(),
      SwapCancelStatus.refusedNotSupported =>
        LocaleKeys.swapCancelRefusedAtomic.tr(),
      SwapCancelStatus.unconfirmed => LocaleKeys.swapCancelUnconfirmed.tr(),
      _ => null,
    };
    final note = copy.leaveNote(web: kIsWeb);
    // What the swap waits on the user for comes first and is the one
    // primary action; leaving is always there, second to it.
    final routePage = snapshot.stage == SwapProgressStage.actionRequired
        ? copy.routePage
        : null;
    final needed = routePage != null
        ? SwapButton(
            key: const Key('swap-open-route'),
            label: LocaleKeys.swapOpenRoutePage.tr(),
            icon: Icons.open_in_new_rounded,
            onPressed: () => openSwapLink(context, '$routePage'),
          )
        : copy.actionNeedsSupport
        ? SwapButton(
            key: const Key('swap-action-support'),
            label: LocaleKeys.swapActionContactSupport.tr(),
            icon: Icons.support_agent_rounded,
            onPressed: () => showSwapEvidenceSheet(
              context,
              snapshot: snapshot,
              services: _services,
            ),
          )
        : null;
    return [
      // A swap waiting on the user is not one that carries on by itself.
      if (snapshot.stage != SwapProgressStage.actionRequired)
        SwapCallout(
          tone: SwapTone.info,
          icon: note.icon,
          message: note.message,
        ),
      if (cancelMessage != null) ...[
        const SizedBox(height: 12),
        // Only a cancel pressed on this screen gets an answer here.
        _arrive(
          SwapCallout(
            tone: SwapTone.warning,
            message: cancelMessage,
            liveRegion: true,
          ),
          live: true,
        ),
      ],
      const SizedBox(height: 16),
      if (needed != null) ...[needed, const SizedBox(height: 10)],
      SwapButton(
        key: const Key('swap-back-to-wallet'),
        label: 'swapBackToWallet'.tr(),
        variant: needed == null
            ? SwapButtonVariant.primary
            : SwapButtonVariant.secondary,
        onPressed: _backToWallet,
      ),
      const SizedBox(height: 10),
      if (snapshot.canCancel) ...[
        SwapButton(
          key: const Key('swap-cancel'),
          label: state.cancelStatus == SwapCancelStatus.cancelling
              ? LocaleKeys.swapCancelling.tr()
              : LocaleKeys.swapCancelSwap.tr(),
          variant: SwapButtonVariant.secondary,
          busy: state.cancelStatus == SwapCancelStatus.cancelling,
          onPressed: () => _confirmCancel(snapshot),
        ),
        const SizedBox(height: 10),
      ],
      if (_inFlow)
        SwapButton(
          label: LocaleKeys.swapViewInActivity.tr(),
          variant: SwapButtonVariant.secondary,
          onPressed: () => _viewInActivity(snapshot),
        ),
    ];
  }

  List<Widget> _recovery(
    BuildContext context,
    SwapExecutionSnapshot snapshot,
    SwapExecutionDisplay copy, {
    required bool live,
  }) {
    final hero = copy.hero;
    final actions = copy.actions;
    final success = snapshot.isSuccess;
    var order = 0;
    Widget arrive(Widget child) => _arrive(child, live: live, order: order++);
    return [
      if (success) ...[
        _receiptBalance(context, snapshot),
        const SizedBox(height: 4),
        // Without an asset to open, the wallet is where the funds are.
        if (copy.presentation.canViewReceivedAsset)
          SwapButton(
            key: const Key('swap-view-asset'),
            label: 'swapViewAsset'.tr(),
            onPressed: () => _backToWallet(received: snapshot),
          )
        else
          SwapButton(
            key: const Key('swap-back-to-wallet'),
            label: 'swapBackToWallet'.tr(),
            onPressed: _backToWallet,
          ),
        const SizedBox(height: 10),
        SwapButton(
          label: 'swapReceiptDetails'.tr(),
          variant: SwapButtonVariant.secondary,
          onPressed: () => showSwapEvidenceSheet(
            context,
            snapshot: snapshot,
            services: _services,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          children: [
            for (final action in actions)
              SwapLinkButton(
                label: _ExecutionBodyState._actionLabel(action, copy),
                onPressed: () => _onAction(action, snapshot),
              ),
            if (copy.presentation.canViewReceivedAsset)
              SwapLinkButton(
                label: 'swapBackToWallet'.tr(),
                onPressed: _backToWallet,
              ),
          ],
        ),
      ],
      if (!success) ...[
        arrive(
          SwapQuestion(
            eyebrow: LocaleKeys.swapQuestionWhat.tr(),
            title: hero.title,
            body: hero.body,
            divider: false,
          ),
        ),
        arrive(
          SwapQuestion(
            eyebrow: LocaleKeys.swapQuestionWhere.tr(),
            body: copy.fundsLocation,
          ),
        ),
        arrive(
          SwapQuestion(
            eyebrow: LocaleKeys.swapQuestionNext.tr(),
            body: LocaleKeys.swapQuestionNextBody.tr(),
          ),
        ),
      ],
      const SizedBox(height: 8),
      if (!success)
        for (final (index, action) in actions.indexed) ...[
          arrive(
            SwapButton(
              label: _ExecutionBodyState._actionLabel(action, copy),
              variant: index == 0
                  ? SwapButtonVariant.primary
                  : SwapButtonVariant.secondary,
              onPressed: () => _onAction(action, snapshot),
            ),
          ),
          const SizedBox(height: 10),
        ],
      if (_inFlow && !success)
        arrive(
          SwapButton(
            label: LocaleKeys.swapViewInActivity.tr(),
            variant: SwapButtonVariant.secondary,
            onPressed: () => _viewInActivity(snapshot),
          ),
        ),
    ];
  }

  /// Whether the wallet's balance shows what arrived yet. One slot of one
  /// height whatever the refresh is doing, so its answer never moves the
  /// action under it.
  Widget _receiptBalance(
    BuildContext context,
    SwapExecutionSnapshot snapshot,
  ) => StreamBuilder<int>(
    stream: _services.presentation.changes,
    builder: (context, _) {
      final status = _services.presentation.balanceStatus(snapshot.id);
      final unavailable = status == SwapReceiptBalanceStatus.unavailable;
      return Semantics(
        container: true,
        liveRegion: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: SwapGeometry.touchTarget,
          ),
          child: Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text(
                  switch (status) {
                    SwapReceiptBalanceStatus.current =>
                      'swapBalanceUpdated'.tr(),
                    SwapReceiptBalanceStatus.unavailable =>
                      'swapBalanceNotRefreshed'.tr(),
                    _ => 'swapUpdatingBalance'.tr(),
                  },
                  key: const Key('swap-receipt-balance'),
                  style: SwapText.small(context),
                  textAlign: TextAlign.center,
                ),
                if (unavailable)
                  SwapLinkButton(
                    key: const Key('swap-receipt-balance-retry'),
                    label: LocaleKeys.tryAgain.tr(),
                    onPressed: () => _services.presentation.refreshReceipt(
                      snapshot,
                      retry: true,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _evidence(
    BuildContext context,
    SwapExecutionSnapshot snapshot, {
    required bool live,
  }) {
    final palette = SwapPalette.of(context);
    final updated = snapshot.updatedAt ?? snapshot.finishedAt;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (updated != null) ...[
            Text(
              LocaleKeys.swapEvidenceUpdated.tr(),
              style: SwapText.eyebrow(context),
            ),
            const SizedBox(height: 2),
            SwapReveal(
              revealKey: updated,
              onMount: false,
              animate: live,
              offset: Offset.zero,
              duration: SwapMotion.colour,
              child: Text(
                SwapFormat.time(updated),
                style: SwapText.body(context),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            LocaleKeys.swapEvidenceExecutionId.tr(),
            style: SwapText.eyebrow(context),
          ),
          SwapCopyLine(
            value: snapshot.id,
            label: LocaleKeys.swapEvidenceExecutionId.tr(),
          ),
          SwapLinkButton(
            label: LocaleKeys.swapActionViewEvidence.tr(),
            icon: Icons.receipt_long_outlined,
            onPressed: () => showSwapEvidenceSheet(
              context,
              snapshot: snapshot,
              services: _services,
            ),
          ),
        ],
      ),
    );
  }
}
