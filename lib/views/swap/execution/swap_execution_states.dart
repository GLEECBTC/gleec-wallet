part of 'swap_execution_view.dart';

/// The screen before it has a swap to show, and what it is titled.
extension _ExecutionStates on _ExecutionBodyState {
  /// The screen's name straight after starting: "progress" only while there
  /// is some to follow.
  String _flowTitle(SwapExecutionSnapshot? snapshot) {
    final outcome = snapshot?.outcome;
    if (outcome == null) return LocaleKeys.swapProgressTitle.tr();
    if (outcome.isSuccess) return LocaleKeys.swapTabCompleted.tr();
    return outcome.kind == SwapOutcomeKind.refunded
        ? LocaleKeys.swapTabRefunded.tr()
        : 'swapProgressEndedTitle'.tr();
  }

  /// No snapshot yet: still loading, the engine not answering, or no source
  /// knowing the swap. Each says which, and what can be done.
  Widget _waiting(BuildContext context, SwapExecutionState state) {
    if (state.notFound) return _notFound(context);
    if (state.unanswered) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ExecutionBodyState._hero(SwapHeroCopy.delayed()),
          SwapCallout(
            tone: SwapTone.info,
            icon: Icons.schedule_rounded,
            message: 'swapProgressStillChecking'.tr(),
          ),
          const SizedBox(height: 16),
          ..._leaveActions(null),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: SwapLoadingStatus(
        label: 'swapProgressLoading'.tr(),
        skeletons: const [
          SwapSkeleton(height: 64, widthFactor: 0.2),
          SizedBox(height: 16),
          SwapSkeleton(widthFactor: 0.6),
          SizedBox(height: 24),
          SwapSkeleton(height: 70),
          SizedBox(height: 8),
          SwapSkeleton(height: 70),
        ],
      ),
    );
  }

  /// The watch ended and nothing knows the swap: looking again may find it,
  /// and Activity lists the ones this wallet does have.
  Widget _notFound(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SwapStatusHero(
        key: const Key('swap-execution-not-found'),
        icon: Icons.search_off_rounded,
        tone: SwapTone.warning,
        title: 'swapProgressNotFoundTitle'.tr(),
        body: 'swapProgressNotFoundBody'.tr(),
      ),
      const SizedBox(height: 8),
      SwapButton(
        key: const Key('swap-not-found-activity'),
        label: (_inFlow ? 'swapOpenActivity' : 'swapBackToActivity').tr(),
        onPressed: _inFlow ? () => _viewInActivity(null) : _leave,
      ),
      const SizedBox(height: 10),
      SwapButton(
        key: const Key('swap-not-found-retry'),
        label: LocaleKeys.tryAgain.tr(),
        variant: SwapButtonVariant.secondary,
        onPressed: widget.onLookAgain,
      ),
    ],
  );

  /// The ways off a swap that asks nothing of the user, the wallet first.
  List<Widget> _leaveActions(SwapExecutionSnapshot? snapshot) => [
    SwapButton(
      key: const Key('swap-back-to-wallet'),
      label: 'swapBackToWallet'.tr(),
      onPressed: _backToWallet,
    ),
    if (_inFlow) ...[
      const SizedBox(height: 10),
      SwapButton(
        label: LocaleKeys.swapViewInActivity.tr(),
        variant: SwapButtonVariant.secondary,
        onPressed: () => _viewInActivity(snapshot),
      ),
    ],
  ];
}
