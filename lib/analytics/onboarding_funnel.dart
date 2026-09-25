import 'package:web_dex/analytics/events/auth_events.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';

/// Tracks one pass through the wallet-setup funnel.
///
/// Emission is deliberately funnelled through a single object rather than
/// sprinkled `logEvent` calls, because `onboarding_step_abandoned` needs a
/// lifecycle hook and a scattered version would make double-firing a matter of
/// review discipline. Here it is structural: exactly one [_current] step is
/// open at a time, [enter] on the step already open is a no-op, and [finish]
/// latches the funnel closed so a late rebuild cannot emit anything.
///
/// Events go through [AnalyticsBloc.logEvent], **not** the `logAuthEvent`
/// helper that sits next to these event classes in `auth_events.dart`. That
/// helper reaches `AnalyticsRepo` through GetIt directly, which makes it
/// invisible to the fake-bloc pattern the widget tests use.
class OnboardingFunnel {
  OnboardingFunnel({
    required AnalyticsBloc analytics,
    required String entryPoint,
    int? Function()? existingWalletCount,
  }) : _analytics = analytics,
       _entryPoint = entryPoint,
       _existingWalletCount = existingWalletCount;

  final AnalyticsBloc _analytics;
  final String _entryPoint;
  final int? Function()? _existingWalletCount;

  OnboardingStep? _current;
  OnboardingFlowKind _flow = OnboardingFlowKind.undecided;
  bool _finished = false;

  /// The step currently open, or null when none is.
  OnboardingStep? get currentStep => _current;

  /// Records which branch of setup the user committed to. Applies to every
  /// subsequent event, including the one closing the current step.
  void setFlow(OnboardingFlowKind flow) {
    _flow = flow;
  }

  /// Opens [step]. No-op when it is already open, or once the funnel has
  /// finished. Any step still open is abandoned first.
  void enter(OnboardingStep step) {
    if (_finished || _current == step) return;
    if (_current != null) abandon();
    _current = step;
    _analytics.logEvent(
      OnboardingStepViewedEventData(
        step: step.slug,
        stepIndex: step.stepIndex,
        flow: _flow.value,
        entryPoint: _entryPoint,
        existingWalletCount: _walletCount(),
      ),
    );
  }

  /// Closes the open step as completed.
  void complete() {
    final step = _current;
    if (_finished || step == null) return;
    _current = null;
    _analytics.logEvent(
      OnboardingStepCompletedEventData(
        step: step.slug,
        stepIndex: step.stepIndex,
        flow: _flow.value,
        entryPoint: _entryPoint,
        existingWalletCount: _walletCount(),
      ),
    );
  }

  /// Closes the open step as abandoned.
  void abandon() {
    final step = _current;
    if (_finished || step == null) return;
    _current = null;
    _analytics.logEvent(
      OnboardingStepAbandonedEventData(
        step: step.slug,
        stepIndex: step.stepIndex,
        flow: _flow.value,
        entryPoint: _entryPoint,
        existingWalletCount: _walletCount(),
      ),
    );
  }

  /// Latches the funnel closed. Use when the user has left onboarding for a
  /// reason that is not a drop-off - a successful sign-in, or a path that was
  /// never onboarding to begin with, such as logging into an existing wallet.
  /// After this, [enter], [complete], [abandon] and [dispose] emit nothing.
  void finish() {
    _current = null;
    _finished = true;
  }

  /// Abandons whatever is still open. Safe to call more than once.
  ///
  /// Widget disposal does not run on a web tab close or an app kill, so this
  /// undercounts by design - see [OnboardingStepAbandonedEventData].
  void dispose() {
    abandon();
    _finished = true;
  }

  int? _walletCount() {
    final read = _existingWalletCount;
    if (read == null) return null;
    try {
      return read();
    } catch (_) {
      // Analytics must never be the reason setup breaks.
      return null;
    }
  }
}
