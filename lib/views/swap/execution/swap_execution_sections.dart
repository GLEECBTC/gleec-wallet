part of 'swap_execution_view.dart';

/// What sits below the timeline: controls while running, the answers once it
/// has stopped, and the evidence either way.
extension _ExecutionSections on _ExecutionBodyState {
  List<Widget> _running(
    BuildContext context,
    SwapExecutionState state,
    SwapExecutionSnapshot snapshot,
  ) {
    final routeUrl = snapshot.evidence.providerExplorerUrl;
    final cancelMessage = switch (state.cancelStatus) {
      SwapCancelStatus.refusedAlreadySent =>
        LocaleKeys.swapCancelRefusedSent.tr(),
      SwapCancelStatus.refusedNotSupported =>
        LocaleKeys.swapCancelRefusedAtomic.tr(),
      SwapCancelStatus.unconfirmed => LocaleKeys.swapCancelUnconfirmed.tr(),
      _ => null,
    };
    return [
      SwapCallout(
        tone: SwapTone.info,
        icon: Icons.schedule_rounded,
        message: LocaleKeys.swapProgressLeaveNote.tr(),
      ),
      if (cancelMessage != null) ...[
        const SizedBox(height: 12),
        SwapCallout(
          tone: SwapTone.warning,
          message: cancelMessage,
          liveRegion: true,
        ),
      ],
      const SizedBox(height: 16),
      if (snapshot.stage == SwapProgressStage.actionRequired &&
          routeUrl != null) ...[
        SwapButton(
          label: LocaleKeys.swapOpenRoutePage.tr(),
          icon: Icons.open_in_new_rounded,
          onPressed: () => openSwapLink(context, routeUrl),
        ),
        const SizedBox(height: 10),
      ],
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
    SwapExecutionCopy copy,
  ) {
    final hero = copy.hero;
    final actions = copy.actions;
    final success = snapshot.isSuccess;
    return [
      if (!success) ...[
        SwapQuestion(
          eyebrow: LocaleKeys.swapQuestionWhat.tr(),
          title: hero.title,
          body: hero.body,
          divider: false,
        ),
        SwapQuestion(
          eyebrow: LocaleKeys.swapQuestionWhere.tr(),
          body: copy.fundsLocation,
        ),
        SwapQuestion(
          eyebrow: LocaleKeys.swapQuestionNext.tr(),
          body: LocaleKeys.swapQuestionNextBody.tr(),
        ),
      ],
      const SizedBox(height: 8),
      for (final (index, action) in actions.indexed) ...[
        SwapButton(
          label: _ExecutionBodyState._actionLabel(action, copy),
          variant: index == 0
              ? SwapButtonVariant.primary
              : SwapButtonVariant.secondary,
          onPressed: () => _onAction(action, snapshot),
        ),
        const SizedBox(height: 10),
      ],
      if (_inFlow)
        SwapButton(
          label: success
              ? LocaleKeys.done.tr()
              : LocaleKeys.swapViewInActivity.tr(),
          variant: SwapButtonVariant.secondary,
          onPressed: success ? _leave : () => _viewInActivity(snapshot),
        ),
    ];
  }

  Widget _evidence(BuildContext context, SwapExecutionSnapshot snapshot) {
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
            Text(SwapFormat.time(updated), style: SwapText.body(context)),
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
