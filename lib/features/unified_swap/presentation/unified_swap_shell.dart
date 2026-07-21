import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:web_dex/features/unified_swap/application/route_activity_bloc.dart';
import 'package:web_dex/features/unified_swap/application/route_execution_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart'
    hide RouteActivityPage;
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/infrastructure/unified_swap_config.dart';
import 'package:web_dex/features/unified_swap/infrastructure/unified_swap_production_composition.dart';
import 'package:web_dex/features/unified_swap/presentation/activity/activity_page.dart';
import 'package:web_dex/features/unified_swap/presentation/swap/unified_swap_page.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_design.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_sensitive_dialog.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/router/state/unified_swap_section_state.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/views/dex/dex_page.dart';

/// Calm Core shell used identically by mobile, tablet, desktop, and web.
///
/// The shell replaces the legacy wallet chrome only while Unified Swap is
/// active. The Gleec logo returns to Wallet and the overflow keeps the existing
/// global destinations reachable without nesting the old navigation.
class UnifiedSwapShell extends StatefulWidget {
  const UnifiedSwapShell({super.key, this.config = const UnifiedSwapConfig()});

  final UnifiedSwapConfig config;

  @override
  State<UnifiedSwapShell> createState() => _UnifiedSwapShellState();
}

class _UnifiedSwapShellState extends State<UnifiedSwapShell> {
  UnifiedSwapConfig get config => widget.config;

  @override
  Widget build(BuildContext context) {
    final route = routingState.unifiedSwapState.value;
    final selected = _navigationDestination(route.destination);
    final colors = UnifiedSwapDesign.colors(context);
    return ScreenshotSensitive(
      child: ColoredBox(
        color: colors.canvas,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scaledBody = MediaQuery.textScalerOf(context).scale(16);
            final desktop =
                constraints.maxWidth >= UnifiedSwapDesign.desktopBreakpoint &&
                (scaledBody < 24 || constraints.maxWidth >= 1200);
            return Column(
              children: [
                _UnifiedSwapHeader(
                  selected: selected,
                  showNavigation: desktop,
                  onSelected: (destination) => _select(context, destination),
                  onWallet: () => _selectGlobal(context, MainMenuValue.wallet),
                  onGlobalSelected: (destination) =>
                      _selectGlobal(context, destination),
                ),
                Expanded(child: _body(context, route)),
                if (!desktop)
                  _UnifiedSwapBottomNavigation(
                    selected: selected,
                    onSelected: (destination) => _select(context, destination),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  UnifiedSwapDestination _navigationDestination(
    UnifiedSwapDestination destination,
  ) {
    return destination == UnifiedSwapDestination.activityDetails
        ? UnifiedSwapDestination.activity
        : destination;
  }

  Future<void> _select(
    BuildContext context,
    UnifiedSwapDestination destination,
  ) async {
    if (_navigationDestination(
          routingState.unifiedSwapState.value.destination,
        ) ==
        _navigationDestination(destination)) {
      return;
    }
    if (!await _confirmDeparture(context)) return;
    if (!mounted || !context.mounted) return;
    routingState.dexState.reset();
    switch (destination) {
      case UnifiedSwapDestination.swap:
        final execution = _maybeExecutionBloc(context);
        final status = execution?.state.status;
        if (execution != null &&
            (status == RouteExecutionLoadStatus.completed ||
                status == RouteExecutionLoadStatus.cancelled ||
                status == RouteExecutionLoadStatus.failed)) {
          execution.add(RouteExecutionWalletChanged(execution.state.walletId));
        }
        routingState.unifiedSwapState.replace(
          const UnifiedSwapRouteState.swap(),
        );
      case UnifiedSwapDestination.activity:
      case UnifiedSwapDestination.activityDetails:
        routingState.unifiedSwapState.replace(
          const UnifiedSwapRouteState.activity(),
        );
      case UnifiedSwapDestination.advanced:
        routingState.unifiedSwapState.replace(
          const UnifiedSwapRouteState.advanced(),
        );
    }
  }

  Future<void> _selectGlobal(
    BuildContext context,
    MainMenuValue destination,
  ) async {
    if (!await _confirmDeparture(context)) return;
    if (!mounted || !context.mounted) return;
    routingState.dexState.reset();
    routingState.selectedMenu = destination;
  }

  Future<bool> _confirmDeparture(BuildContext context) async {
    final state = _maybeExecutionBloc(context)?.state;
    if (state == null ||
        state.status == RouteExecutionLoadStatus.idle ||
        state.status == RouteExecutionLoadStatus.completed ||
        state.status == RouteExecutionLoadStatus.cancelled ||
        state.status == RouteExecutionLoadStatus.failed) {
      return true;
    }
    final reviewing = state.status == RouteExecutionLoadStatus.reviewRequired;
    return showUnifiedSwapSensitiveConfirmation(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          unifiedSwapText(
            dialogContext,
            reviewing
                ? 'navigation.leaveReviewTitle'
                : 'navigation.leaveExecutionTitle',
            reviewing ? 'Leave this Review?' : 'Leave swap progress?',
          ),
        ),
        content: Text(
          unifiedSwapText(
            dialogContext,
            reviewing
                ? 'navigation.leaveReviewBody'
                : 'navigation.leaveExecutionBody',
            reviewing
                ? 'No swap has started. Leaving discards this prepared '
                      'Review.'
                : 'The swap continues in Activity. Leaving this screen '
                      'does not cancel it.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              unifiedSwapText(dialogContext, 'common.stay', 'Stay here'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              unifiedSwapText(dialogContext, 'common.leave', 'Leave'),
            ),
          ),
        ],
      ),
    );
  }

  void _viewActivity(String routeExecutionId) {
    routingState.unifiedSwapState.replace(
      UnifiedSwapRouteState.activityDetails(routeExecutionId),
    );
  }

  Widget _body(BuildContext context, UnifiedSwapRouteState route) {
    switch (route.destination) {
      case UnifiedSwapDestination.swap:
        final production = _maybeProductionComposition(context);
        return UnifiedSwapPage(
          config: config,
          maximumAmountResolver: production?.maximumAmount,
          selectionGateway: production,
          initialAmountDraft: route.legacyHints.sourceAmount,
          onViewActivity: _viewActivity,
        );
      case UnifiedSwapDestination.activity:
        return RouteActivityPage(
          onStartSwap: () => _select(context, UnifiedSwapDestination.swap),
          onExecutionSelected: _viewActivity,
        );
      case UnifiedSwapDestination.activityDetails:
        return _UnifiedSwapActivityDetail(
          config: config,
          routeExecutionId: route.routeExecutionId,
        );
      case UnifiedSwapDestination.advanced:
        return DexPage(legacyHints: route.legacyHints);
    }
  }
}

/// Connects authoritative Activity history to the wallet-scoped durable
/// execution coordinator. Live progress and controls are exposed only after
/// that coordinator has reattached the exact route and KDF has supplied a
/// current executable snapshot.
class _UnifiedSwapActivityDetail extends StatefulWidget {
  const _UnifiedSwapActivityDetail({
    required this.config,
    required this.routeExecutionId,
  });

  final UnifiedSwapConfig config;
  final String? routeExecutionId;

  @override
  State<_UnifiedSwapActivityDetail> createState() =>
      _UnifiedSwapActivityDetailState();
}

class _UnifiedSwapActivityDetailState
    extends State<_UnifiedSwapActivityDetail> {
  RouteExecutionBloc? _executionBloc;
  String? _requestedRouteExecutionId;
  String? _failedRouteExecutionId;
  bool _showLiveExecution = false;
  bool _labelLiveActionAsResume = false;
  bool _openProgressAfterReattach = false;
  bool _controlAttemptPending = false;
  String? _controlFailureRouteExecutionId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = _maybeExecutionBloc(context);
    if (!identical(next, _executionBloc)) {
      _executionBloc = next;
      _requestedRouteExecutionId = null;
      _failedRouteExecutionId = null;
      _labelLiveActionAsResume = false;
      _openProgressAfterReattach = false;
      _controlAttemptPending = false;
      _controlFailureRouteExecutionId = null;
    }
  }

  @override
  void didUpdateWidget(_UnifiedSwapActivityDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeExecutionId != widget.routeExecutionId) {
      _requestedRouteExecutionId = null;
      _failedRouteExecutionId = null;
      _showLiveExecution = false;
      _labelLiveActionAsResume = false;
      _openProgressAfterReattach = false;
      _controlAttemptPending = false;
      _controlFailureRouteExecutionId = null;
    }
  }

  void _requestProgressReattachment(String requestedRouteExecutionId) {
    final bloc = _executionBloc;
    final routeExecutionId = widget.routeExecutionId;
    if (bloc == null ||
        bloc.state.walletId == null ||
        routeExecutionId == null ||
        requestedRouteExecutionId != routeExecutionId ||
        routeExecutionId.trim().isEmpty ||
        _requestedRouteExecutionId == routeExecutionId ||
        !_hasResumableActivityDetail(routeExecutionId) ||
        !_canRequestProgressReattachment(bloc.state, routeExecutionId)) {
      return;
    }
    setState(() {
      _labelLiveActionAsResume = true;
      _requestedRouteExecutionId = routeExecutionId;
      _failedRouteExecutionId = null;
      _openProgressAfterReattach = true;
    });
    bloc.add(RouteExecutionReattachRequested(routeExecutionId));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _requestedRouteExecutionId != routeExecutionId) {
        return;
      }
      final current = _executionBloc?.state;
      final accepted =
          current != null &&
          (current.status == RouteExecutionLoadStatus.reattaching ||
              current.session?.routeExecutionId == routeExecutionId ||
              current.progress?.routeExecutionId == routeExecutionId);
      if (!accepted) {
        setState(() {
          _requestedRouteExecutionId = null;
          _openProgressAfterReattach = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final routeExecutionId = widget.routeExecutionId;
    final bloc = _executionBloc;
    final activityBloc = _maybeActivityBloc(context);
    if (routeExecutionId == null || bloc == null || activityBloc == null) {
      return RouteActivityPage(
        showDetails: true,
        initialRouteExecutionId: routeExecutionId,
        onBack: _backToActivity,
      );
    }
    final hasResumableActivityDetail = context.select<RouteActivityBloc, bool>(
      (activity) => _isResumableActivityDetail(
        activity.state.selectedExecution,
        routeExecutionId,
      ),
    );
    return BlocConsumer<RouteExecutionBloc, RouteExecutionState>(
      bloc: bloc,
      listenWhen: (previous, current) =>
          _attachmentSettled(previous, current) ||
          _activityProjectionChanged(previous, current, routeExecutionId),
      listener: (_, state) => _executionStateChanged(
        routeExecutionId: routeExecutionId,
        state: state,
      ),
      builder: (context, state) {
        if (_showLiveExecution) {
          final production = _maybeProductionComposition(context);
          return UnifiedSwapPage(
            config: widget.config,
            initialRouteExecutionId: routeExecutionId,
            maximumAmountResolver: production?.maximumAmount,
            selectionGateway: production,
            onViewActivity: (_) => setState(() => _showLiveExecution = false),
          );
        }
        final progress = state.progress;
        final matches =
            state.session?.routeExecutionId == routeExecutionId &&
            progress?.routeExecutionId == routeExecutionId &&
            progress!.isExecutable;
        final controls = progress?.controls;
        final controlTarget = state.controlTarget;
        final pending = progress?.pendingAction;
        final liveProgressReady =
            hasResumableActivityDetail &&
            matches &&
            state.failure == null &&
            _isLiveProgressStatus(state.status) &&
            !_isTerminalOutcome(progress.outcome);
        final canRetryLiveProgress =
            hasResumableActivityDetail &&
            _failedRouteExecutionId == routeExecutionId &&
            state.failure != null &&
            _isRetryableProgressFailure(state.failure!) &&
            !state.controlInFlight;
        final canResumeLiveProgress =
            hasResumableActivityDetail &&
            !liveProgressReady &&
            !canRetryLiveProgress &&
            _requestedRouteExecutionId != routeExecutionId &&
            _canRequestProgressReattachment(state, routeExecutionId);
        return RouteActivityPage(
          showDetails: true,
          initialRouteExecutionId: routeExecutionId,
          onBack: _backToActivity,
          onCancelRequested:
              matches &&
                  controlTarget != null &&
                  controls!.canCancel &&
                  !controls.reconciliationOnly
              ? (confirmedRouteExecutionId) => _cancel(
                  confirmedRouteExecutionId,
                  expectedBloc: bloc,
                  expectedTarget: controlTarget,
                )
              : null,
          onStopAfterCurrentRequested:
              matches &&
                  controlTarget != null &&
                  controls!.canStopAfterCurrent &&
                  !controls.reconciliationOnly
              ? (confirmedRouteExecutionId) => _stopAfterCurrent(
                  confirmedRouteExecutionId,
                  expectedBloc: bloc,
                  expectedTarget: controlTarget,
                )
              : null,
          onRecoveryRequested:
              matches &&
                  pending != null &&
                  pending.isExecutable &&
                  pending.allowedActions.contains(
                    RouteExecutionActionKind.selectRecoveryRoute,
                  )
              ? _openRecovery
              : null,
          onProgressRequested: liveProgressReady ? _openProgress : null,
          onProgressReattachRequested: canRetryLiveProgress
              ? _retryProgress
              : canResumeLiveProgress
              ? _resumeProgress
              : null,
          progressReattachFailed: canRetryLiveProgress,
          resumeProgress: _labelLiveActionAsResume,
          liveControlInFlight: matches && state.controlInFlight,
          liveControlFailure:
              _controlFailureRouteExecutionId == routeExecutionId
              ? unifiedSwapText(
                  context,
                  'activity.detail.controlFailed',
                  'The requested control could not be applied. The latest '
                      'route state is still shown; review it before trying '
                      'again.',
                )
              : null,
        );
      },
    );
  }

  void _executionStateChanged({
    required String routeExecutionId,
    required RouteExecutionState state,
  }) {
    final inFlight =
        state.status == RouteExecutionLoadStatus.starting ||
        state.status == RouteExecutionLoadStatus.reattaching;
    final exactBinding =
        state.session?.routeExecutionId == routeExecutionId ||
        state.progress?.routeExecutionId == routeExecutionId;
    if (_controlAttemptPending && !state.controlInFlight && exactBinding) {
      _controlAttemptPending = false;
      _controlFailureRouteExecutionId = state.failure == null
          ? null
          : routeExecutionId;
      if (mounted) setState(() {});
    }
    if (!inFlight &&
        state.failure != null &&
        (_requestedRouteExecutionId == routeExecutionId || exactBinding)) {
      // Keep a failed exact handoff explicitly retryable, but do not turn a
      // transient failure into an automatic reattach loop.
      _requestedRouteExecutionId = null;
      _failedRouteExecutionId = routeExecutionId;
      _openProgressAfterReattach = false;
    } else if (state.failure == null && exactBinding) {
      _failedRouteExecutionId = null;
      if (_openProgressAfterReattach &&
          _hasResumableActivityDetail(routeExecutionId) &&
          _hasExactLiveProgress(state, routeExecutionId)) {
        _requestedRouteExecutionId = null;
        _openProgressAfterReattach = false;
        if (mounted) setState(() => _showLiveExecution = true);
      }
    }
    _refreshActivity();
  }

  void _cancel(
    String routeExecutionId, {
    required RouteExecutionBloc expectedBloc,
    required RouteExecutionControlTarget expectedTarget,
  }) {
    final bloc = _executionBloc;
    if (!mounted ||
        bloc == null ||
        bloc.isClosed ||
        !identical(bloc, expectedBloc) ||
        expectedTarget.routeExecutionId != routeExecutionId ||
        bloc.state.controlTarget != expectedTarget ||
        !_hasResumableActivityDetail(routeExecutionId) ||
        !_matchesCurrentSession(routeExecutionId)) {
      return;
    }
    setState(() {
      _controlAttemptPending = true;
      _controlFailureRouteExecutionId = null;
    });
    bloc.add(RouteExecutionCancelRequested(expectedTarget));
  }

  void _stopAfterCurrent(
    String routeExecutionId, {
    required RouteExecutionBloc expectedBloc,
    required RouteExecutionControlTarget expectedTarget,
  }) {
    final bloc = _executionBloc;
    if (!mounted ||
        bloc == null ||
        bloc.isClosed ||
        !identical(bloc, expectedBloc) ||
        expectedTarget.routeExecutionId != routeExecutionId ||
        bloc.state.controlTarget != expectedTarget ||
        !_hasResumableActivityDetail(routeExecutionId) ||
        !_matchesCurrentSession(routeExecutionId)) {
      return;
    }
    setState(() {
      _controlAttemptPending = true;
      _controlFailureRouteExecutionId = null;
    });
    bloc.add(RouteExecutionStopAfterCurrentRequested(expectedTarget));
  }

  void _openRecovery(String routeExecutionId) {
    if (!_hasResumableActivityDetail(routeExecutionId) ||
        !_matchesCurrentSession(routeExecutionId)) {
      return;
    }
    setState(() => _showLiveExecution = true);
  }

  void _openProgress(String routeExecutionId) {
    final state = _executionBloc?.state;
    final progress = state?.progress;
    if (!_hasResumableActivityDetail(routeExecutionId) ||
        !_matchesCurrentSession(routeExecutionId) ||
        state == null ||
        progress == null ||
        !progress.isExecutable ||
        state.controlInFlight ||
        state.failure != null ||
        !_isLiveProgressStatus(state.status) ||
        _isTerminalOutcome(progress.outcome)) {
      return;
    }
    setState(() => _showLiveExecution = true);
  }

  void _resumeProgress(String routeExecutionId) {
    _requestProgressReattachment(routeExecutionId);
  }

  void _retryProgress(String routeExecutionId) {
    final state = _executionBloc?.state;
    if (routeExecutionId != widget.routeExecutionId ||
        _failedRouteExecutionId != routeExecutionId ||
        state == null ||
        state.controlInFlight ||
        state.failure == null ||
        !_isRetryableProgressFailure(state.failure!)) {
      return;
    }
    _requestedRouteExecutionId = null;
    _requestProgressReattachment(routeExecutionId);
  }

  bool _canRequestProgressReattachment(
    RouteExecutionState state,
    String routeExecutionId,
  ) {
    if (state.walletId == null ||
        state.controlInFlight ||
        state.status == RouteExecutionLoadStatus.reviewRequired ||
        state.status == RouteExecutionLoadStatus.starting ||
        state.status == RouteExecutionLoadStatus.reattaching ||
        _wouldDisplaceNonterminalSession(state, routeExecutionId) ||
        _hasExactLiveProgress(state, routeExecutionId)) {
      return false;
    }
    final retryingExactFailure =
        _failedRouteExecutionId == routeExecutionId &&
        state.failure != null &&
        _isRetryableProgressFailure(state.failure!);
    if (retryingExactFailure) return true;
    if (_failedRouteExecutionId == routeExecutionId && state.failure != null) {
      // Permanent, conflicting, or unsupported exact handoffs stay inert.
      return false;
    }
    if (_requestedRouteExecutionId == routeExecutionId ||
        state.session?.routeExecutionId == routeExecutionId ||
        state.progress?.routeExecutionId == routeExecutionId) {
      // An acknowledged or in-flight exact handoff owns this route. Wait for
      // executable progress; unknown or incomplete snapshots stay inert.
      return false;
    }
    return true;
  }

  bool _hasResumableActivityDetail(String routeExecutionId) {
    final activity = _maybeActivityBloc(context);
    return activity != null &&
        _isResumableActivityDetail(
          activity.state.selectedExecution,
          routeExecutionId,
        );
  }

  void _refreshActivity() {
    final activity = _maybeActivityBloc(context);
    if (activity == null || activity.state.walletId == null) return;
    if (activity.state.isDetailLoading &&
        activity.state.selectedExecution == null) {
      // An exact Activity GET owns the detail generation while it is loading.
      // Let it settle before reconciliation so the handoff cannot cancel it.
      return;
    }
    activity.add(const RouteActivityRefreshRequested());
  }

  bool _matchesCurrentSession(String routeExecutionId) =>
      routeExecutionId == widget.routeExecutionId &&
      _executionBloc?.state.session?.routeExecutionId == routeExecutionId &&
      _executionBloc?.state.progress?.routeExecutionId == routeExecutionId;

  void _backToActivity() => routingState.unifiedSwapState.replace(
    const UnifiedSwapRouteState.activity(),
  );
}

RouteExecutionBloc? _maybeExecutionBloc(BuildContext context) {
  try {
    return context.read<RouteExecutionBloc>();
  } on Object {
    return null;
  }
}

UnifiedSwapProductionComposition? _maybeProductionComposition(
  BuildContext context,
) {
  try {
    return context.read<UnifiedSwapProductionComposition>();
  } on Object {
    return null;
  }
}

RouteActivityBloc? _maybeActivityBloc(BuildContext context) {
  try {
    return context.read<RouteActivityBloc>();
  } on Object {
    return null;
  }
}

bool _attachmentSettled(
  RouteExecutionState previous,
  RouteExecutionState current,
) =>
    (previous.status == RouteExecutionLoadStatus.starting ||
        previous.status == RouteExecutionLoadStatus.reattaching) &&
    current.status != RouteExecutionLoadStatus.starting &&
    current.status != RouteExecutionLoadStatus.reattaching;

bool _activityProjectionChanged(
  RouteExecutionState previous,
  RouteExecutionState current,
  String routeExecutionId,
) {
  final previousProgress = previous.progress;
  final currentProgress = current.progress;
  final concernsExactRoute =
      previousProgress?.routeExecutionId == routeExecutionId ||
      currentProgress?.routeExecutionId == routeExecutionId ||
      current.session?.routeExecutionId == routeExecutionId;
  if (!concernsExactRoute) return false;
  return previousProgress?.stateRevision != currentProgress?.stateRevision ||
      previousProgress?.outcome != currentProgress?.outcome ||
      previousProgress?.controls != currentProgress?.controls ||
      previous.status != current.status ||
      previous.controlInFlight != current.controlInFlight ||
      previous.failure != current.failure;
}

bool _isLiveProgressStatus(RouteExecutionLoadStatus status) =>
    status == RouteExecutionLoadStatus.observing ||
    status == RouteExecutionLoadStatus.attentionRequired ||
    status == RouteExecutionLoadStatus.recovery;

bool _isTerminalOutcome(RouteExecutionOutcome outcome) =>
    outcome == RouteExecutionOutcome.completed ||
    outcome == RouteExecutionOutcome.cancelled ||
    outcome == RouteExecutionOutcome.failed;

bool _isRetryableProgressFailure(RouteExecutionFailure failure) =>
    failure == RouteExecutionFailure.networkUnavailable ||
    failure == RouteExecutionFailure.storageUnavailable ||
    failure == RouteExecutionFailure.serviceUnavailable ||
    failure == RouteExecutionFailure.unknown;

bool _hasExactLiveProgress(RouteExecutionState state, String routeExecutionId) {
  final progress = state.progress;
  return state.session?.routeExecutionId == routeExecutionId &&
      progress?.routeExecutionId == routeExecutionId &&
      progress!.isExecutable &&
      !state.controlInFlight &&
      state.failure == null &&
      _isLiveProgressStatus(state.status) &&
      !_isTerminalOutcome(progress.outcome);
}

bool _wouldDisplaceNonterminalSession(
  RouteExecutionState state,
  String routeExecutionId,
) {
  final session = state.session;
  if (session == null || session.routeExecutionId == routeExecutionId) {
    return false;
  }
  final progress = state.progress;
  if (progress == null ||
      progress.routeExecutionId != session.routeExecutionId) {
    return true;
  }
  return !_isTerminalOutcome(progress.outcome);
}

bool _isResumableActivityDetail(
  RouteExecutionDetail? detail,
  String routeExecutionId,
) {
  if (detail == null ||
      detail.summary.routeExecutionId != routeExecutionId ||
      detail.summary.status.isTerminal ||
      detail.summary.status == RouteActivityStatus.unknown ||
      detail.summary.terminalError != null) {
    return false;
  }
  final status = detail.authoritativeStatus;
  if (status == null || !status.isExecutable) return false;
  final executionTerminal =
      status.executionPhase == RouteActivityExecutionPhase.failed ||
      status.executionPhase == RouteActivityExecutionPhase.cancelled ||
      status.executionPhase == RouteActivityExecutionPhase.refunded;
  final routeTerminal =
      status.routePhase == RouteExecutionRoutePhase.completed ||
      status.routePhase == RouteExecutionRoutePhase.failed ||
      status.routePhase == RouteExecutionRoutePhase.cancelled ||
      status.routePhase == RouteExecutionRoutePhase.refunded;
  final historicalRefund =
      detail.controls.reconciliationOnly &&
      (status.executionPhase == RouteActivityExecutionPhase.refundPending ||
          status.executionPhase == RouteActivityExecutionPhase.refunded ||
          status.routePhase == RouteExecutionRoutePhase.refundPending ||
          status.routePhase == RouteExecutionRoutePhase.refunded);
  return !executionTerminal && !routeTerminal && !historicalRefund;
}

class _UnifiedSwapHeader extends StatelessWidget {
  const _UnifiedSwapHeader({
    required this.selected,
    required this.showNavigation,
    required this.onSelected,
    required this.onWallet,
    required this.onGlobalSelected,
  });

  final UnifiedSwapDestination selected;
  final bool showNavigation;
  final ValueChanged<UnifiedSwapDestination> onSelected;
  final VoidCallback onWallet;
  final ValueChanged<MainMenuValue> onGlobalSelected;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return Material(
      color: colors.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 10, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: unifiedSwapText(
                  context,
                  'shell.walletLogo',
                  'Gleec Wallet',
                ),
                child: InkWell(
                  key: const Key('unified-swap-logo'),
                  onTap: onWallet,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          'assets/logo/g_icon.svg',
                          width: 25,
                          height: 32,
                        ),
                        const SizedBox(width: 9),
                        SvgPicture.asset(
                          Theme.of(context).brightness == Brightness.dark
                              ? 'assets/logo/logo_dark.svg'
                              : 'assets/logo/logo.svg',
                          width: 112,
                          height: 25,
                          fit: BoxFit.contain,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (showNavigation)
                Semantics(
                  container: true,
                  label: LocaleKeys.unifiedSwap_navigationLabel.tr(),
                  child: FocusTraversalGroup(
                    child: Row(
                      children: [
                        for (final destination in const [
                          UnifiedSwapDestination.swap,
                          UnifiedSwapDestination.activity,
                          UnifiedSwapDestination.advanced,
                        ])
                          _UnifiedSwapNavigationItem(
                            destination: destination,
                            selected: selected == destination,
                            onPressed: () => onSelected(destination),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              _GlobalOverflowButton(onSelected: onGlobalSelected),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnifiedSwapBottomNavigation extends StatelessWidget {
  const _UnifiedSwapBottomNavigation({
    required this.selected,
    required this.onSelected,
  });

  final UnifiedSwapDestination selected;
  final ValueChanged<UnifiedSwapDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              for (final destination in const [
                UnifiedSwapDestination.swap,
                UnifiedSwapDestination.activity,
                UnifiedSwapDestination.advanced,
              ])
                Expanded(
                  child: _UnifiedSwapNavigationItem(
                    destination: destination,
                    selected: selected == destination,
                    vertical: true,
                    onPressed: () => onSelected(destination),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnifiedSwapNavigationItem extends StatelessWidget {
  const _UnifiedSwapNavigationItem({
    required this.destination,
    required this.selected,
    required this.onPressed,
    this.vertical = false,
  });

  final UnifiedSwapDestination destination;
  final bool selected;
  final VoidCallback onPressed;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final (label, icon) = switch (destination) {
      UnifiedSwapDestination.swap => (
        unifiedSwapText(context, 'navigation.swap', 'Swap'),
        Icons.hub_outlined,
      ),
      UnifiedSwapDestination.activity ||
      UnifiedSwapDestination.activityDetails => (
        unifiedSwapText(context, 'navigation.activity', 'Activity'),
        Icons.history_toggle_off_rounded,
      ),
      UnifiedSwapDestination.advanced => (
        unifiedSwapText(context, 'navigation.advanced', 'Advanced'),
        Icons.show_chart_rounded,
      ),
    };
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: vertical ? 2 : 2),
        child: Material(
          color: selected ? colors.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: Key('unified-swap-nav-${destination.name}'),
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: vertical ? 6 : 14,
                  vertical: vertical ? 5 : 10,
                ),
                child: vertical
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 18,
                            color: selected
                                ? colors.textPrimary
                                : colors.textSecondary,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            label,
                            maxLines: 1,
                            style: UnifiedSwapDesign.typography(context)
                                .labelSmall
                                .copyWith(
                                  color: selected
                                      ? colors.textPrimary
                                      : colors.textSecondary,
                                ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            icon,
                            size: 18,
                            color: selected
                                ? colors.textPrimary
                                : colors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: UnifiedSwapDesign.typography(context)
                                .labelMedium
                                .copyWith(
                                  color: selected
                                      ? colors.textPrimary
                                      : colors.textSecondary,
                                ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlobalOverflowButton extends StatelessWidget {
  const _GlobalOverflowButton({required this.onSelected});

  final ValueChanged<MainMenuValue> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return PopupMenuButton<MainMenuValue>(
      key: const Key('unified-swap-global-overflow'),
      tooltip: unifiedSwapText(
        context,
        'shell.moreDestinations',
        'More wallet destinations',
      ),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final destination in const [
          MainMenuValue.wallet,
          MainMenuValue.settings,
          MainMenuValue.support,
        ])
          PopupMenuItem(value: destination, child: Text(destination.title)),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const SizedBox.square(
          dimension: 48,
          child: Icon(Icons.more_vert_rounded),
        ),
      ),
    );
  }
}
