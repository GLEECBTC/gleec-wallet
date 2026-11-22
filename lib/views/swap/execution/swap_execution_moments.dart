part of 'swap_execution_view.dart';

/// Explicit attention and new completion are the only execution haptics.
/// The session claim prevents duplicate effects across simultaneous views.
extension _ExecutionMoments on _ExecutionBodyState {
  void _onNews(BuildContext context, SwapExecutionState state) {
    final before = _heard;
    final after = state.snapshot;
    _heard = after;
    if (after == null) return;
    if (_visible == true) {
      _services.presentation.markSeen(after);
      _services.presentation.refreshReceipt(after);
    }
    if (!state.live || before == null || _visible != true) return;
    final changed =
        before.stage != after.stage ||
        before.outcome?.kind != after.outcome?.kind;
    if (!changed) return;
    _animateMoment = _services.presentation.claimMoment(after);
    if (!_animateMoment) return;
    if (after.isSuccess && before.outcome == null) {
      SwapHaptics.success();
    } else if (after.stage == SwapProgressStage.actionRequired &&
        before.stage != SwapProgressStage.actionRequired) {
      SwapHaptics.warning();
    }
  }
}
