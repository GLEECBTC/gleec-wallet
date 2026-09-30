part of 'swap_execution_view.dart';

/// What sits below the timeline: controls while running, the answers once it
/// has stopped, and the evidence either way.
/// When the sections below the timeline start arriving after a live change:
/// once the hero has begun to settle.
const _sectionDelay = Duration(milliseconds: 160);

extension _ExecutionSections on _ExecutionBodyState {
  /// Brings in the [order]th section that arrived with a live change.
  Widget _arrive(Widget child, {required bool live, int order = 0}) =>
      SwapReveal(
        onMount: live,
        animate: live,
        delay: _sectionDelay + SwapMotion.stagger * order,
        child: child,
      );

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
      if (snapshot.stage == SwapProgressStage.actionRequired &&
          routeUrl != null) ...[
        _arrive(
          SwapButton(
            label: LocaleKeys.swapOpenRoutePage.tr(),
            icon: Icons.open_in_new_rounded,
            onPressed: () => openSwapLink(context, routeUrl),
          ),
          live: state.live,
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
    SwapExecutionCopy copy, {
    required bool live,
  }) {
    final hero = copy.hero;
    final actions = copy.actions;
    final success = snapshot.isSuccess;
    var order = 0;
    Widget arrive(Widget child) => _arrive(child, live: live, order: order++);
    return [
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
      if (_inFlow)
        arrive(
          SwapButton(
            label: success
                ? LocaleKeys.done.tr()
                : LocaleKeys.swapViewInActivity.tr(),
            variant: SwapButtonVariant.secondary,
            onPressed: success ? _leave : () => _viewInActivity(snapshot),
          ),
        ),
    ];
  }

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
