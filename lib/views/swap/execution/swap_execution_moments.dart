part of 'swap_execution_view.dart';

/// Marks news of a swap as it arrives while the screen is open: a haptic for
/// how it ended, for the swap waiting on the user, and for a step completing.
/// Reopening a swap, or news from the watch's replay, plays none of them.
extension _ExecutionMoments on _ExecutionBodyState {
  void _onNews(BuildContext context, SwapExecutionState state) {
    final before = _heard;
    final after = state.snapshot;
    _heard = after;
    if (!state.live || before == null || after == null) return;
    if (!TickerMode.valuesOf(context).enabled) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;

    final outcome = after.outcome;
    if (outcome != null) {
      if (before.outcome == null) _outcomeHaptic(outcome.kind, after)();
      return;
    }
    if (after.stage == SwapProgressStage.actionRequired) {
      if (before.stage != SwapProgressStage.actionRequired) {
        SwapHaptics.warning();
      }
      return;
    }
    if (_stepsDone(after) > _stepsDone(before)) SwapHaptics.selection();
  }

  int _stepsDone(SwapExecutionSnapshot snapshot) => SwapTimeline.of(
    snapshot,
    _services.networks(),
  ).where((step) => step.status == SwapStepStatus.done).length;

  void Function() _outcomeHaptic(
    SwapOutcomeKind kind,
    SwapExecutionSnapshot snapshot,
  ) => switch (kind) {
    SwapOutcomeKind.completed => SwapHaptics.success,
    SwapOutcomeKind.refunded || SwapOutcomeKind.noMatch => SwapHaptics.light,
    SwapOutcomeKind.cancelled => SwapHaptics.selection,
    SwapOutcomeKind.failed
        when SwapExecutionCopy(snapshot, _services.networks()).hero.tone ==
            SwapTone.danger =>
      SwapHaptics.error,
    _ => SwapHaptics.warning,
  };
}
