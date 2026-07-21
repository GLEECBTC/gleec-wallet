import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/features/unified_swap/application/route_execution_bloc.dart';
import 'package:web_dex/features/unified_swap/application/unified_swap_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_product_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_selection_models.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_unified_swap_review_coordinator.dart';
import 'package:web_dex/features/unified_swap/infrastructure/unified_swap_config.dart';
import 'package:web_dex/features/unified_swap/infrastructure/unified_swap_production_composition.dart';
import 'package:web_dex/features/unified_swap/presentation/swap/route_execution_view.dart';
import 'package:web_dex/features/unified_swap/presentation/swap/route_review_view.dart';
import 'package:web_dex/features/unified_swap/presentation/swap/swap_entry_view.dart';
import 'package:web_dex/features/unified_swap/presentation/swap/swap_widgets.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_design.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_sensitive_dialog.dart';
import 'package:web_dex/router/state/routing_state.dart';

typedef UnifiedSwapReviewBuilder =
    Future<RouteExecutionReview?> Function({
      required UnifiedSwapIntent intent,
      required UnifiedSwapQuoteCandidate candidate,
    });

typedef UnifiedSwapRecoveryReviewSelector =
    Future<String?> Function(RouteExecutionProgress progress);

/// Presentation-only coordinator for quote, Review, and execution BLoCs.
///
/// It never owns or closes an injected BLoC. Disposing this page therefore
/// detaches local observation widgets without sending a backend route control.
/// Exact consent creation and gas-aware Max are explicit wallet-composition
/// dependencies and fail closed when absent.
class UnifiedSwapPage extends StatefulWidget {
  const UnifiedSwapPage({
    required this.config,
    this.quoteBloc,
    this.executionBloc,
    this.reviewBuilder,
    this.maximumAmountResolver,
    this.recipientValidator,
    this.selectionGateway,
    this.recoveryReviewSelector,
    this.initialRouteExecutionId,
    this.initialAmountDraft,
    this.onViewActivity,
    this.clipboardWriter = defaultSwapClipboardWriter,
    this.announcement = defaultSwapAnnouncement,
    this.manageLifecycle = true,
    this.now,
    super.key,
  });

  final UnifiedSwapConfig config;
  final UnifiedSwapBloc? quoteBloc;
  final RouteExecutionBloc? executionBloc;
  final UnifiedSwapReviewBuilder? reviewBuilder;
  final UnifiedSwapMaximumAmountResolver? maximumAmountResolver;
  final UnifiedSwapRecipientValidator? recipientValidator;
  final UnifiedSwapSelectionGateway? selectionGateway;
  final UnifiedSwapRecoveryReviewSelector? recoveryReviewSelector;
  final String? initialRouteExecutionId;
  final String? initialAmountDraft;
  final ValueChanged<String>? onViewActivity;
  final SwapClipboardWriter clipboardWriter;
  final SwapAnnouncement announcement;
  final bool manageLifecycle;
  final DateTime Function()? now;

  @override
  State<UnifiedSwapPage> createState() => _UnifiedSwapPageState();
}

class _UnifiedSwapPageState extends State<UnifiedSwapPage>
    with WidgetsBindingObserver {
  UnifiedSwapBloc? _quoteBloc;
  RouteExecutionBloc? _executionBloc;
  String? _reattachRequestedFor;
  bool _reviewInFlight = false;
  bool _recoveryDraftInFlight = false;
  String? _reviewFailure;
  int _reviewGeneration = 0;
  UnifiedSwapRecoveryDraft? _recoveryDraft;
  RouteExecutionReview? _recoveryReview;
  String? _editDismissedReviewId;
  bool _reviewPickerOpen = false;
  String? _reviewPickerReviewId;
  int _reviewPickerRevision = 0;
  final GlobalKey _entryKey = GlobalKey(
    debugLabel: 'Unified Swap editable entry',
  );
  final FocusNode _reviewOpenerFocusNode = FocusNode(
    debugLabel: 'Unified Swap Review opener',
  );

  @override
  void initState() {
    super.initState();
    if (widget.manageLifecycle) WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _quoteBloc = widget.quoteBloc ?? _maybeBloc<UnifiedSwapBloc>(context);
    final execution =
        widget.executionBloc ?? _maybeBloc<RouteExecutionBloc>(context);
    if (!identical(_executionBloc, execution)) _reattachRequestedFor = null;
    _executionBloc = execution;
    _requestInitialReattach();
    _syncBrowserNavigationBlock();
  }

  @override
  void didUpdateWidget(UnifiedSwapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quoteBloc != widget.quoteBloc) {
      _reviewGeneration++;
      _quoteBloc = widget.quoteBloc ?? _maybeBloc<UnifiedSwapBloc>(context);
    }
    if (oldWidget.executionBloc != widget.executionBloc) {
      _executionBloc =
          widget.executionBloc ?? _maybeBloc<RouteExecutionBloc>(context);
      _reattachRequestedFor = null;
    }
    if (oldWidget.initialRouteExecutionId != widget.initialRouteExecutionId) {
      _reattachRequestedFor = null;
    }
    _requestInitialReattach();
    _syncBrowserNavigationBlock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.manageLifecycle || state != AppLifecycleState.resumed) return;
    final bloc = _executionBloc;
    final status = bloc?.state.status;
    if (bloc?.state.routeExecutionId != null &&
        status != RouteExecutionLoadStatus.idle &&
        status != RouteExecutionLoadStatus.reviewRequired &&
        status != RouteExecutionLoadStatus.starting &&
        status != RouteExecutionLoadStatus.reattaching) {
      bloc!.add(const RouteExecutionAppResumed());
    }
  }

  @override
  void dispose() {
    _reviewGeneration++;
    _reviewOpenerFocusNode.dispose();
    if (widget.manageLifecycle) WidgetsBinding.instance.removeObserver(this);
    routingState.isBrowserNavigationBlocked = false;
    super.dispose();
  }

  void _syncBrowserNavigationBlock() {
    final status = _executionBloc?.state.status;
    routingState.isBrowserNavigationBlocked =
        status != null &&
        status != RouteExecutionLoadStatus.idle &&
        status != RouteExecutionLoadStatus.completed &&
        status != RouteExecutionLoadStatus.cancelled &&
        status != RouteExecutionLoadStatus.failed;
  }

  void _requestInitialReattach() {
    final execution = _executionBloc;
    final routeExecutionId = widget.initialRouteExecutionId;
    if (execution == null ||
        execution.state.walletId == null ||
        routeExecutionId == null ||
        routeExecutionId.trim().isEmpty ||
        _reattachRequestedFor == routeExecutionId ||
        execution.state.routeExecutionId == routeExecutionId) {
      return;
    }
    _reattachRequestedFor = routeExecutionId;
    execution.add(RouteExecutionReattachRequested(routeExecutionId));
  }

  void _submitControl(
    RouteExecutionBloc expectedBloc,
    RouteExecutionControlTarget expectedTarget, {
    required bool stopAfterCurrent,
  }) {
    if (!mounted ||
        expectedBloc.isClosed ||
        !identical(_executionBloc, expectedBloc) ||
        expectedBloc.state.controlTarget != expectedTarget) {
      return;
    }
    expectedBloc.add(
      stopAfterCurrent
          ? RouteExecutionStopAfterCurrentRequested(expectedTarget)
          : RouteExecutionCancelRequested(expectedTarget),
    );
  }

  Future<void> _prepareReview(UnifiedSwapQuoteCandidate candidate) async {
    final quote = _quoteBloc;
    final execution = _executionBloc;
    final recoveryDraft = _recoveryDraft;
    final coordinator = widget.reviewBuilder == null
        ? _reviewCoordinator(context)
        : null;
    final builder = recoveryDraft == null
        ? widget.reviewBuilder ?? coordinator?.prepareReview
        : coordinator?.prepareReview;
    final intent = quote?.state.intent;
    final walletId = execution?.state.walletId;
    if (!widget.config.canExecute ||
        quote == null ||
        execution == null ||
        builder == null ||
        intent == null ||
        walletId == null ||
        quote.state.selectedCandidateId != candidate.candidateId ||
        !isSafeSwapCandidate(candidate)) {
      setState(() {
        _reviewFailure = unifiedSwapText(
          context,
          'review.failure.consentUnavailable',
          'Exact wallet-bound execution consent is not available. No funds '
              'moved.',
        );
      });
      return;
    }
    setState(() {
      _reviewInFlight = true;
      _reviewFailure = null;
    });
    final generation = ++_reviewGeneration;
    try {
      final review = recoveryDraft == null
          ? await builder(intent: intent, candidate: candidate)
          : await coordinator!.prepareRecoveryReview(
              routeExecutionId: recoveryDraft.routeExecutionId,
              intent: intent,
              candidate: candidate,
            );
      final currentIntent = mounted ? quote.state.intent : null;
      final currentProgress = execution.state.progress;
      final stale =
          !mounted ||
          generation != _reviewGeneration ||
          !identical(_quoteBloc, quote) ||
          !identical(_executionBloc, execution) ||
          currentIntent == null ||
          quote.state.status != UnifiedSwapQuoteStatus.ready ||
          quote.state.selectedCandidateId != candidate.candidateId ||
          currentIntent.revision != intent.revision ||
          review == null ||
          execution.state.walletId != walletId ||
          review.walletId != walletId ||
          review.candidateDigest != candidate.candidateDigest ||
          !review.source.sameIdentity(intent.source) ||
          !review.destination.sameIdentity(intent.destination) ||
          review.sourceAmount != intent.sourceAmount ||
          !_isQuietPreparedReceive(
            quoted: candidate.expectedReceive,
            prepared: review.expectedReceive,
          ) ||
          review.minimumReceive != candidate.minimumReceive ||
          review.recipient != intent.recipient ||
          review.expiresAt.isAfter(candidate.expiresAt) ||
          review.sourceSelectorKind != intent.sourceSelection.kind ||
          review.externalRecipientConfirmed !=
              intent.externalRecipientConfirmed ||
          (recoveryDraft != null &&
              (!identical(_recoveryDraft, recoveryDraft) ||
                  review.routeExecutionId != recoveryDraft.routeExecutionId ||
                  !_recoveryProgressMatches(recoveryDraft, currentProgress)));
      if (stale) {
        if (review != null) coordinator?.discardReview(review);
        if (mounted && generation == _reviewGeneration) {
          setState(() {
            _reviewFailure = unifiedSwapText(
              context,
              'review.failure.preparedMismatch',
              'The prepared Review did not match the selected exact route. '
                  'No funds moved.',
            );
          });
        }
        return;
      }
      if (recoveryDraft == null) {
        execution.add(RouteExecutionReviewPresented(review));
      } else {
        setState(() => _recoveryReview = review);
      }
    } on Object {
      if (mounted && generation == _reviewGeneration) {
        setState(() {
          _reviewFailure = unifiedSwapText(
            context,
            'review.failure.prepareFailed',
            'The wallet could not prepare exact route consent. No funds moved.',
          );
        });
      }
    } finally {
      if (mounted && generation == _reviewGeneration) {
        setState(() => _reviewInFlight = false);
      }
    }
  }

  Future<void> _submitDecision(RouteExecutionActionKind kind) async {
    final bloc = _executionBloc;
    final progress = bloc?.state.progress;
    final pending = progress?.pendingAction;
    if (bloc == null ||
        progress == null ||
        pending == null ||
        !progress.isExecutable ||
        !pending.isExecutable ||
        !pending.allowedActions.contains(kind)) {
      return;
    }
    String? recoveryReviewId;
    if (kind == RouteExecutionActionKind.selectRecoveryRoute) {
      final selector = widget.recoveryReviewSelector;
      if (selector == null) {
        await _beginRecovery(progress);
        return;
      }
      try {
        recoveryReviewId = await selector(progress);
      } on Object {
        return;
      }
      if (!mounted ||
          recoveryReviewId == null ||
          recoveryReviewId.trim().isEmpty) {
        return;
      }
    }
    bloc.add(
      RouteExecutionDecisionSubmitted(
        RouteExecutionDecision(
          kind: kind,
          actionId: pending.actionId,
          expectedStateRevision: progress.stateRevision,
          recoveryReviewId: recoveryReviewId,
          replacementProposalDigest:
              kind == RouteExecutionActionKind.acceptReplacement
              ? pending.replacementProposal?.proposalDigest
              : null,
        ),
      ),
    );
  }

  Future<void> _beginRecovery(RouteExecutionProgress progress) async {
    if (_recoveryDraftInFlight) return;
    final quote = _quoteBloc;
    final composition = _productionComposition(context);
    if (quote == null || composition == null || !widget.config.canExecute) {
      return;
    }
    setState(() {
      _recoveryDraftInFlight = true;
      _reviewFailure = null;
    });
    final generation = ++_reviewGeneration;
    try {
      final draft = await composition.recoveryDraft(
        progress,
        intentRevision: (quote.state.intent?.revision ?? -1) + 1,
      );
      if (!mounted ||
          generation != _reviewGeneration ||
          draft == null ||
          !_recoveryProgressMatches(draft, _executionBloc?.state.progress)) {
        return;
      }
      var intent = draft.intent;
      if (!draft.recipientIsWalletOwned) {
        final confirmed = await _confirmExternalRecipient(
          recovery: true,
          intent: intent,
        );
        if (!mounted || generation != _reviewGeneration || !confirmed) return;
        intent = intent.copyWith(externalRecipientConfirmed: true);
      }
      setState(() {
        _recoveryDraft = draft;
        _recoveryReview = null;
        _reviewFailure = null;
      });
      quote.add(UnifiedSwapIntentChanged(intent));
    } finally {
      if (mounted && generation == _reviewGeneration) {
        setState(() => _recoveryDraftInFlight = false);
      }
    }
  }

  Future<bool> _onIntentChanged(
    UnifiedSwapIntent intent, {
    VoidCallback? onWillCommit,
  }) async {
    final quote = _quoteBloc;
    if (quote == null || !mounted) return false;
    bool commit(UnifiedSwapIntent next) {
      if (!mounted) return false;
      onWillCommit?.call();
      quote.add(UnifiedSwapIntentChanged(next));
      return true;
    }

    final previous = quote.state.intent;
    final recipientContextUnchanged =
        previous != null &&
        intent.recipient == previous.recipient &&
        intent.destination.sameIdentity(previous.destination);
    if (previous == null || recipientContextUnchanged) {
      final next = recipientContextUnchanged
          ? intent.copyWith(
              externalRecipientConfirmed: previous.externalRecipientConfirmed,
            )
          : intent;
      if (_reviewFailure != null) setState(() => _reviewFailure = null);
      return commit(next);
    }
    if (intent.externalRecipientConfirmed) {
      if (_reviewFailure != null) setState(() => _reviewFailure = null);
      return commit(intent);
    }
    final composition = _productionComposition(context);
    if (composition == null) {
      setState(() {
        _reviewFailure = unifiedSwapText(
          context,
          'recipient.verificationUnavailable',
          'The wallet could not verify ownership of this recipient. The swap '
              'stayed unchanged.',
        );
      });
      return false;
    }
    final generation = ++_reviewGeneration;
    bool? owned;
    try {
      owned = await composition.recipientIsWalletOwned(
        asset: intent.destination,
        address: intent.recipient,
      );
    } on Object {
      if (mounted && generation == _reviewGeneration) {
        setState(() {
          _reviewFailure = unifiedSwapText(
            context,
            'recipient.verificationUnavailable',
            'The wallet could not verify ownership of this recipient. The '
                'swap stayed unchanged.',
          );
        });
      }
      return false;
    }
    if (!mounted ||
        generation != _reviewGeneration ||
        quote.state.intent?.revision != previous.revision) {
      return false;
    }
    if (owned == null) {
      setState(() {
        _reviewFailure = unifiedSwapText(
          context,
          'recipient.verificationUnavailable',
          'The wallet could not verify ownership of this recipient. The swap '
              'stayed unchanged.',
        );
      });
      return false;
    }
    if (owned) {
      if (_reviewFailure != null) setState(() => _reviewFailure = null);
      return commit(intent.copyWith(externalRecipientConfirmed: false));
    }
    if (await _confirmExternalRecipient(recovery: false, intent: intent) &&
        mounted &&
        generation == _reviewGeneration &&
        quote.state.intent?.revision == previous.revision) {
      if (_reviewFailure != null) setState(() => _reviewFailure = null);
      return commit(intent.copyWith(externalRecipientConfirmed: true));
    }
    return false;
  }

  Future<bool> _confirmExternalRecipient({
    required bool recovery,
    required UnifiedSwapIntent intent,
  }) async {
    final result = await showUnifiedSwapSensitiveConfirmation(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          recovery
              ? unifiedSwapText(
                  dialogContext,
                  'recipient.recoveryTitle',
                  'Confirm recovery recipient',
                )
              : unifiedSwapText(
                  dialogContext,
                  'recipient.externalTitle',
                  'External recipient',
                ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  recovery
                      ? unifiedSwapText(
                          dialogContext,
                          'recipient.recoveryBody',
                          'Recovery will use the original external destination '
                              'address. Confirm it again before requesting a '
                              'fresh route.',
                        )
                      : unifiedSwapText(
                          dialogContext,
                          'recipient.externalBody',
                          'This address is not owned by the active wallet. '
                              'Confirm the destination network and recipient '
                              'before continuing.',
                        ),
                ),
                const SizedBox(height: 16),
                SwapSectionCard(
                  title: unifiedSwapText(
                    dialogContext,
                    'recipient.youWillReceive',
                    'You will receive',
                  ),
                  icon: Icons.call_received_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        intent.destination.ticker,
                        style: UnifiedSwapDesign.typography(
                          dialogContext,
                        ).cardTitle,
                      ),
                      Text(
                        unifiedSwapNetworkLabel(
                          dialogContext,
                          intent.destination,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SwapCopyableValue(
                  label: unifiedSwapText(
                    dialogContext,
                    'recipient.fullAddress',
                    'Full receiving address',
                  ),
                  value: intent.recipient,
                  valueKey: 'swap-external-recipient',
                  clipboardWriter: widget.clipboardWriter,
                  announcement: widget.announcement,
                ),
                const SizedBox(height: 12),
                UnifiedSwapNotice(
                  title: unifiedSwapText(
                    dialogContext,
                    'recipient.checkExternalTitle',
                    'Check this external address',
                  ),
                  message: unifiedSwapText(
                    dialogContext,
                    'recipient.checkExternalBody',
                    'Make sure you control it and that it supports {asset} on '
                        '{network}. Completed transfers can’t be reversed.',
                    namedArgs: {
                      'asset': intent.destination.ticker,
                      'network': unifiedSwapNetworkLabel(
                        dialogContext,
                        intent.destination,
                      ),
                    },
                  ),
                  tone: UnifiedSwapNoticeTone.warning,
                  icon: Icons.location_on_outlined,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              unifiedSwapText(dialogContext, 'common.goBack', 'Go back'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              unifiedSwapText(
                dialogContext,
                'recipient.confirm',
                'Confirm recipient',
              ),
            ),
          ),
        ],
      ),
    );
    return result;
  }

  void _acceptRecoveryReview() {
    final draft = _recoveryDraft;
    final review = _recoveryReview;
    final bloc = _executionBloc;
    final progress = bloc?.state.progress;
    if (draft == null ||
        review == null ||
        bloc == null ||
        review.routeExecutionId != draft.routeExecutionId ||
        review.isExpiredAt(widget.now?.call() ?? DateTime.now().toUtc()) ||
        !_recoveryProgressMatches(draft, progress)) {
      return;
    }
    bloc.add(
      RouteExecutionDecisionSubmitted(
        RouteExecutionDecision(
          kind: RouteExecutionActionKind.selectRecoveryRoute,
          actionId: draft.actionId,
          expectedStateRevision: draft.expectedStateRevision,
          recoveryReviewId: review.reviewId,
        ),
      ),
    );
    setState(() {
      _recoveryDraft = null;
      _recoveryReview = null;
      _reviewFailure = null;
    });
  }

  void _dismissPreparedReview(
    RouteExecutionReview review, {
    bool restoreFocus = true,
  }) {
    final execution = _executionBloc;
    if (execution == null ||
        execution.state.status != RouteExecutionLoadStatus.reviewRequired ||
        execution.state.review != review) {
      return;
    }
    if (widget.reviewBuilder == null) {
      _reviewCoordinator(context)?.discardReview(review);
    }
    _reviewGeneration++;
    setState(() {
      _reviewInFlight = false;
      _reviewFailure = null;
    });
    execution.add(const RouteExecutionReviewDismissed());
    if (restoreFocus) _restoreReviewOpenerFocus();
  }

  void _beginPreparedReviewEdit(RouteExecutionReview review) {
    if (_editDismissedReviewId == review.reviewId) return;
    final execution = _executionBloc;
    if (execution == null ||
        execution.state.status != RouteExecutionLoadStatus.reviewRequired ||
        execution.state.review != review) {
      return;
    }
    _editDismissedReviewId = review.reviewId;
    _dismissPreparedReview(review, restoreFocus: false);
  }

  void _handleReviewPickerPresentation(
    RouteExecutionReview review,
    bool visible,
  ) {
    final execution = _executionBloc;
    if (visible) {
      if (execution?.state.status != RouteExecutionLoadStatus.reviewRequired ||
          execution?.state.review != review) {
        return;
      }
      _reviewPickerRevision++;
      if (_reviewPickerOpen && _reviewPickerReviewId == review.reviewId) return;
      setState(() {
        _reviewPickerOpen = true;
        _reviewPickerReviewId = review.reviewId;
      });
      return;
    }
    final revision = ++_reviewPickerRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _reviewPickerRevision) return;
      if (_editDismissedReviewId == review.reviewId) return;
      setState(() {
        _reviewPickerOpen = false;
        _reviewPickerReviewId = null;
      });
    });
  }

  void _cancelRecovery() {
    final review = _recoveryReview;
    if (review != null) _reviewCoordinator(context)?.discardReview(review);
    _reviewGeneration++;
    setState(() {
      _recoveryDraft = null;
      _recoveryReview = null;
      _recoveryDraftInFlight = false;
      _reviewFailure = null;
    });
    _restoreReviewOpenerFocus();
  }

  void _restoreReviewOpenerFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _reviewOpenerFocusNode.canRequestFocus) {
        _reviewOpenerFocusNode.requestFocus();
      }
    });
  }

  Future<void> _requestLeaveExecution(
    BuildContext pickerContext,
    RouteExecutionState executionState,
  ) async {
    final routeExecutionId = executionState.routeExecutionId;
    final onViewActivity = widget.onViewActivity;
    if (routeExecutionId == null || onViewActivity == null) return;
    if (_isTerminalExecutionStatus(executionState.status)) {
      onViewActivity(routeExecutionId);
      return;
    }
    await showUnifiedSwapPicker<void>(
      context: pickerContext,
      title: unifiedSwapText(
        pickerContext,
        'execution.continuesTitle',
        'Swap continues in Activity',
      ),
      subtitle: unifiedSwapText(
        pickerContext,
        'execution.continuesSubtitle',
        'You can leave this screen and return to the exact saved step.',
      ),
      builder: (surfaceContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UnifiedSwapStatusHero(
            title: unifiedSwapText(
              surfaceContext,
              'execution.continuesTitle',
              'Swap continues in Activity',
            ),
            message: unifiedSwapText(
              surfaceContext,
              'execution.continuesBody',
              'Closing progress only stops local observation. It never '
                  'cancels backend execution.',
            ),
            icon: Icons.schedule_rounded,
            tone: UnifiedSwapNoticeTone.brand,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('swap-leave-view-activity'),
            style: UnifiedSwapDesign.primaryButtonStyle(surfaceContext),
            onPressed: () {
              completeUnifiedSwapPicker(surfaceContext);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) onViewActivity(routeExecutionId);
              });
            },
            child: Text(
              unifiedSwapText(
                surfaceContext,
                'execution.viewActivity',
                'View Activity',
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('swap-leave-dismiss'),
            style: UnifiedSwapDesign.secondaryButtonStyle(surfaceContext),
            onPressed: () => completeUnifiedSwapPicker(surfaceContext),
            child: Text(
              unifiedSwapText(surfaceContext, 'common.dismiss', 'Dismiss'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _announce(RouteLiveAnnouncement announcement) async {
    final message = _announcement(context, announcement);
    if (message == null || !mounted) return;
    try {
      await widget.announcement(context, message);
    } on Object {
      // The visible live region remains the accessibility fallback.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.config.canQuote) {
      return SwapUnavailable(
        key: const Key('swap-quote-switch-disabled'),
        title: unifiedSwapText(
          context,
          'unavailableTitle',
          'Unified Swap is unavailable',
        ),
        message: unifiedSwapText(
          context,
          'quoteDisabled',
          'New route quotes are disabled. Existing executions remain '
              'available in Activity for status and recovery.',
        ),
      );
    }
    final quote = _quoteBloc;
    if (quote == null) {
      return SwapUnavailable(
        key: const Key('swap-quote-dependency-unavailable'),
        title: unifiedSwapText(
          context,
          'unavailableTitle',
          'Unified Swap is unavailable',
        ),
        message: unifiedSwapText(
          context,
          'walletUnavailableBody',
          'Connect an authenticated, supported wallet before requesting an '
              'executable route.',
        ),
      );
    }
    final execution = _executionBloc;
    if (execution == null) {
      return BlocBuilder<UnifiedSwapBloc, UnifiedSwapState>(
        bloc: quote,
        builder: (context, quoteState) => UnifiedSwapEntryView(
          key: _entryKey,
          state: quoteState,
          onIntentChanged: _onIntentChanged,
          onCandidateSelected: (id) =>
              quote.add(UnifiedSwapCandidateSelected(id)),
          onRevalidate: () =>
              quote.add(const UnifiedSwapRevalidationRequested()),
          onReviewRequested: _prepareReview,
          canReview: false,
          reviewUnavailableMessage: unifiedSwapText(
            context,
            'review.unavailableCoordinator',
            'Execution is unavailable until the wallet provides a '
                'wallet-scoped execution coordinator.',
          ),
          maximumAmountResolver: widget.maximumAmountResolver,
          recipientValidator:
              widget.recipientValidator ??
              _productionComposition(context)?.validateRecipient,
          selectionGateway:
              widget.selectionGateway ?? _productionComposition(context),
          reviewInFlight: _reviewInFlight,
          reviewFailure: _reviewFailure,
          reviewFocusNode: _reviewOpenerFocusNode,
          initialAmountDraft: widget.initialAmountDraft,
          now: widget.now,
        ),
      );
    }
    return BlocListener<RouteExecutionBloc, RouteExecutionState>(
      bloc: execution,
      listenWhen: (previous, current) =>
          previous.status != current.status ||
          previous.announcement != current.announcement ||
          previous.walletId != current.walletId ||
          previous.freshQuote != current.freshQuote,
      listener: (context, state) {
        _syncBrowserNavigationBlock();
        _requestInitialReattach();
        unawaited(_announce(state.announcement));
        final freshQuote = state.freshQuote;
        if (freshQuote != null) {
          quote.add(
            UnifiedSwapFreshEvaluationAdopted(
              intent: freshQuote.intent,
              evaluation: freshQuote.evaluation,
            ),
          );
          setState(() {
            _reviewFailure = unifiedSwapText(
              context,
              'review.refresh.structureChanged',
              'The route changed. Review the fresh options before continuing.',
            );
          });
          _restoreReviewOpenerFocus();
        }
        final draft = _recoveryDraft;
        if (draft != null && !_recoveryProgressMatches(draft, state.progress)) {
          _cancelRecovery();
        }
      },
      child: BlocBuilder<RouteExecutionBloc, RouteExecutionState>(
        bloc: execution,
        builder: (context, executionState) {
          if (executionState.status !=
              RouteExecutionLoadStatus.reviewRequired) {
            _editDismissedReviewId = null;
          }
          if (_reviewPickerOpen &&
              (executionState.status !=
                      RouteExecutionLoadStatus.reviewRequired ||
                  executionState.review?.reviewId != _reviewPickerReviewId)) {
            _reviewPickerOpen = false;
            _reviewPickerReviewId = null;
            _reviewPickerRevision++;
          }
          if (_recoveryDraft case final draft?) {
            return _recoveryBody(
              quote: quote,
              executionState: executionState,
              draft: draft,
            );
          }
          if ((executionState.status ==
                      RouteExecutionLoadStatus.reviewRequired ||
                  executionState.status == RouteExecutionLoadStatus.starting) &&
              executionState.review != null) {
            final review = executionState.review!;
            final reviewEditable =
                executionState.status ==
                RouteExecutionLoadStatus.reviewRequired;
            return RouteReviewView(
              key: ValueKey<int>(Object.hash('swap-review', review.reviewId)),
              review: review,
              desktopIntentEditor:
                  BlocBuilder<UnifiedSwapBloc, UnifiedSwapState>(
                    bloc: quote,
                    builder: (context, quoteState) => ExcludeFocus(
                      excluding: !reviewEditable,
                      child: AbsorbPointer(
                        absorbing: !reviewEditable,
                        child: UnifiedSwapEntryView(
                          key: _entryKey,
                          state: quoteState,
                          onIntentChanged: (intent) => _onIntentChanged(
                            intent,
                            onWillCommit: () =>
                                _beginPreparedReviewEdit(review),
                          ),
                          onIntentEditStarted: reviewEditable
                              ? () => _beginPreparedReviewEdit(review)
                              : null,
                          onCandidateSelected: (id) {
                            if (!reviewEditable) return;
                            _beginPreparedReviewEdit(review);
                            quote.add(UnifiedSwapCandidateSelected(id));
                          },
                          onRevalidate: () {
                            if (!reviewEditable) return;
                            _beginPreparedReviewEdit(review);
                            quote.add(const UnifiedSwapRevalidationRequested());
                          },
                          onReviewRequested: _prepareReview,
                          canReview: false,
                          reviewUnavailableMessage: unifiedSwapText(
                            context,
                            'review.sidePanelBody',
                            'Editing the swap closes this Review and checks a '
                                'fresh quote.',
                          ),
                          maximumAmountResolver: widget.maximumAmountResolver,
                          recipientValidator:
                              widget.recipientValidator ??
                              _productionComposition(
                                context,
                              )?.validateRecipient,
                          selectionGateway:
                              widget.selectionGateway ??
                              _productionComposition(context),
                          intentEditable: reviewEditable,
                          reviewInFlight: !reviewEditable,
                          reviewFailure: _reviewFailure,
                          reviewFocusNode: _reviewOpenerFocusNode,
                          onPickerPresentationChanged: (visible) =>
                              _handleReviewPickerPresentation(review, visible),
                          now: widget.now,
                        ),
                      ),
                    ),
                  ),
              onBack:
                  executionState.status ==
                      RouteExecutionLoadStatus.reviewRequired
                  ? () => _dismissPreparedReview(review)
                  : null,
              onAccept: () => execution.add(
                RouteExecutionReviewAccepted(
                  reviewId: review.reviewId,
                  consentDigest: review.consentDigest,
                ),
              ),
              acceptInFlight:
                  executionState.status == RouteExecutionLoadStatus.starting,
              executionEnabled: widget.config.canExecute,
              clipboardWriter: widget.clipboardWriter,
              announcement: widget.announcement,
              failureMessage: _reviewExecutionFailure(
                context,
                executionState.failure,
                executionState.reviewRefreshStatus,
              ),
              termsUpdated:
                  executionState.reviewRefreshStatus ==
                  RouteReviewRefreshStatus.materialChange,
              previousReview: executionState.previousReview,
              desktopIntentSurfaceOpen:
                  reviewEditable &&
                  _reviewPickerOpen &&
                  _reviewPickerReviewId == review.reviewId,
              now: widget.now,
            );
          }
          if (executionState.status != RouteExecutionLoadStatus.idle) {
            return UnifiedSwapPickerHost(
              child: Builder(
                builder: (pickerContext) => RouteExecutionView(
                  state: executionState,
                  onReattach: () {
                    final routeExecutionId = executionState.routeExecutionId;
                    if (routeExecutionId != null) {
                      execution.add(
                        RouteExecutionReattachRequested(routeExecutionId),
                      );
                    }
                  },
                  onCancel: () {
                    final target = executionState.controlTarget;
                    if (target != null) {
                      _submitControl(
                        execution,
                        target,
                        stopAfterCurrent: false,
                      );
                    }
                  },
                  onStopAfterCurrent: () {
                    final target = executionState.controlTarget;
                    if (target != null) {
                      _submitControl(execution, target, stopAfterCurrent: true);
                    }
                  },
                  onDecision: (kind) => unawaited(_submitDecision(kind)),
                  canSelectRecoveryRoute:
                      widget.recoveryReviewSelector != null ||
                      (_productionComposition(context) != null &&
                          widget.config.canExecute),
                  clipboardWriter: widget.clipboardWriter,
                  announcement: widget.announcement,
                  onClose: widget.onViewActivity == null
                      ? null
                      : () => unawaited(
                          _requestLeaveExecution(pickerContext, executionState),
                        ),
                  onViewActivity:
                      widget.onViewActivity == null ||
                          executionState.routeExecutionId == null
                      ? null
                      : () => widget.onViewActivity!(
                          executionState.routeExecutionId!,
                        ),
                ),
              ),
            );
          }
          return BlocBuilder<UnifiedSwapBloc, UnifiedSwapState>(
            bloc: quote,
            builder: (context, quoteState) => UnifiedSwapEntryView(
              key: _entryKey,
              state: quoteState,
              onIntentChanged: _onIntentChanged,
              onCandidateSelected: (id) =>
                  quote.add(UnifiedSwapCandidateSelected(id)),
              onRevalidate: () =>
                  quote.add(const UnifiedSwapRevalidationRequested()),
              onReviewRequested: _prepareReview,
              canReview:
                  widget.config.canExecute &&
                  _reviewBuilder(context) != null &&
                  executionState.walletId != null,
              reviewUnavailableMessage: _reviewUnavailableMessage(
                executionState,
              ),
              maximumAmountResolver: widget.maximumAmountResolver,
              recipientValidator:
                  widget.recipientValidator ??
                  _productionComposition(context)?.validateRecipient,
              selectionGateway:
                  widget.selectionGateway ?? _productionComposition(context),
              reviewInFlight: _reviewInFlight,
              reviewFailure: _reviewFailure,
              reviewFocusNode: _reviewOpenerFocusNode,
              initialAmountDraft: widget.initialAmountDraft,
              now: widget.now,
            ),
          );
        },
      ),
    );
  }

  Widget _recoveryBody({
    required UnifiedSwapBloc quote,
    required RouteExecutionState executionState,
    required UnifiedSwapRecoveryDraft draft,
  }) {
    final review = _recoveryReview;
    final body = review != null
        ? RouteReviewView(
            review: review,
            desktopIntentEditor: BlocBuilder<UnifiedSwapBloc, UnifiedSwapState>(
              bloc: quote,
              builder: (context, quoteState) => UnifiedSwapEntryView(
                key: ValueKey('recovery-review-${draft.expectedStateRevision}'),
                state: quoteState,
                onIntentChanged: (_) async => false,
                onCandidateSelected: (_) {},
                onRevalidate: () {},
                onReviewRequested: (_) {},
                canReview: false,
                reviewUnavailableMessage: unifiedSwapText(
                  context,
                  'review.recoveryUnavailable',
                  'Recovery requires a fresh prepared Review for the exact '
                      'verified holding.',
                ),
                intentEditable: false,
                reviewInFlight: executionState.controlInFlight,
                reviewFailure: _reviewFailure,
                now: widget.now,
              ),
            ),
            onBack: executionState.controlInFlight ? null : _cancelRecovery,
            onAccept: _acceptRecoveryReview,
            acceptInFlight: executionState.controlInFlight,
            executionEnabled:
                widget.config.canExecute &&
                _recoveryProgressMatches(draft, executionState.progress),
            clipboardWriter: widget.clipboardWriter,
            announcement: widget.announcement,
            failureMessage: _reviewFailure,
            now: widget.now,
          )
        : BlocBuilder<UnifiedSwapBloc, UnifiedSwapState>(
            bloc: quote,
            builder: (context, quoteState) {
              if (!_recoveryIntentMatches(draft, quoteState.intent)) {
                return Center(
                  key: const Key('swap-recovery-quote-loading'),
                  child: CircularProgressIndicator(
                    semanticsLabel: unifiedSwapText(
                      context,
                      'recovery.preparingQuote',
                      'Preparing recovery quote',
                    ),
                  ),
                );
              }
              return UnifiedSwapEntryView(
                key: ValueKey('recovery-${draft.expectedStateRevision}'),
                state: quoteState,
                onIntentChanged: _onIntentChanged,
                onCandidateSelected: (id) =>
                    quote.add(UnifiedSwapCandidateSelected(id)),
                onRevalidate: () =>
                    quote.add(const UnifiedSwapRevalidationRequested()),
                onReviewRequested: _prepareReview,
                canReview:
                    widget.config.canExecute &&
                    _reviewCoordinator(context) != null &&
                    _recoveryProgressMatches(draft, executionState.progress),
                reviewUnavailableMessage: unifiedSwapText(
                  context,
                  'review.recoveryUnavailable',
                  'Recovery requires a fresh prepared Review for the exact '
                      'verified holding.',
                ),
                maximumAmountResolver: null,
                intentEditable: false,
                reviewInFlight: _reviewInFlight,
                reviewFailure: _reviewFailure,
                reviewFocusNode: _reviewOpenerFocusNode,
                now: widget.now,
              );
            },
          );
    return Column(
      key: const Key('unified-swap-recovery-composition'),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('swap-recovery-back-to-status'),
            onPressed: executionState.controlInFlight ? null : _cancelRecovery,
            icon: const Icon(Icons.arrow_back_rounded),
            label: Text(
              unifiedSwapText(
                context,
                'recovery.backToStatus',
                'Back to recovery status',
              ),
            ),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  String _reviewUnavailableMessage(RouteExecutionState state) {
    if (!widget.config.canExecute) {
      return unifiedSwapText(
        context,
        'review.unavailableExecutionDisabled',
        'New execution is disabled. Existing routes remain available in '
            'Activity.',
      );
    }
    if (state.walletId == null) {
      return unifiedSwapText(
        context,
        'review.unavailableWallet',
        'An authenticated wallet scope is required before Review.',
      );
    }
    if (_reviewBuilder(context) == null) {
      return unifiedSwapText(
        context,
        'review.unavailableConsent',
        'Exact consent preparation is unavailable. Review remains disabled.',
      );
    }
    return '';
  }

  UnifiedSwapReviewBuilder? _reviewBuilder(BuildContext context) {
    final injected = widget.reviewBuilder;
    if (injected != null) return injected;
    return _reviewCoordinator(context)?.prepareReview;
  }

  KdfUnifiedSwapReviewCoordinator? _reviewCoordinator(BuildContext context) {
    try {
      return context.read<KdfUnifiedSwapReviewCoordinator>();
    } on Object {
      return null;
    }
  }

  UnifiedSwapProductionComposition? _productionComposition(
    BuildContext context,
  ) {
    try {
      return context.read<UnifiedSwapProductionComposition>();
    } on Object {
      return null;
    }
  }
}

bool _recoveryProgressMatches(
  UnifiedSwapRecoveryDraft draft,
  RouteExecutionProgress? progress,
) {
  final pending = progress?.pendingAction;
  return progress != null &&
      progress.isExecutable &&
      progress.routeExecutionId == draft.routeExecutionId &&
      progress.stateRevision == draft.expectedStateRevision &&
      pending != null &&
      pending.isExecutable &&
      pending.actionId == draft.actionId &&
      pending.reason == RoutePendingActionReason.recoveryRequired &&
      pending.allowedActions.contains(
        RouteExecutionActionKind.selectRecoveryRoute,
      );
}

bool _isTerminalExecutionStatus(RouteExecutionLoadStatus status) =>
    status == RouteExecutionLoadStatus.completed ||
    status == RouteExecutionLoadStatus.cancelled ||
    status == RouteExecutionLoadStatus.failed;

bool _recoveryIntentMatches(
  UnifiedSwapRecoveryDraft draft,
  UnifiedSwapIntent? intent,
) =>
    intent != null &&
    intent.source.sameIdentity(draft.intent.source) &&
    intent.destination.sameIdentity(draft.intent.destination) &&
    intent.sourceAmount == draft.intent.sourceAmount &&
    intent.sourceSelection == draft.intent.sourceSelection &&
    intent.recipient == draft.intent.recipient &&
    (draft.recipientIsWalletOwned || intent.externalRecipientConfirmed);

T? _maybeBloc<T extends StateStreamableSource<Object?>>(BuildContext context) {
  try {
    return context.read<T>();
  } on Object {
    return null;
  }
}

bool _isQuietPreparedReceive({
  required String quoted,
  required String prepared,
}) {
  final quotedValue = BigInt.parse(quoted);
  final preparedValue = BigInt.parse(prepared);
  if (preparedValue >= quotedValue) return true;
  if (quotedValue == BigInt.zero) return false;
  return (quotedValue - preparedValue) * BigInt.from(10000) <=
      quotedValue * BigInt.from(unifiedSwapQuietRefreshMaximumDegradationBps);
}

String? _reviewExecutionFailure(
  BuildContext context,
  RouteExecutionFailure? failure,
  RouteReviewRefreshStatus refreshStatus,
) {
  if (failure != null &&
      refreshStatus == RouteReviewRefreshStatus.latestTermsUnavailable) {
    return unifiedSwapText(
      context,
      'review.refresh.unavailable',
      'Latest route terms could not be verified. Nothing started; try again.',
    );
  }
  return switch (failure) {
    RouteExecutionFailure.invalidReview => unifiedSwapText(
      context,
      'review.failure.invalidReview',
      'The Review no longer matches exact wallet consent.',
    ),
    RouteExecutionFailure.reviewExpired => unifiedSwapText(
      context,
      'review.failure.expired',
      'The Review expired. Obtain a fresh quote before continuing.',
    ),
    RouteExecutionFailure.capabilityUnavailable => unifiedSwapText(
      context,
      'review.failure.capabilityChanged',
      'Wallet capability changed before funds moved.',
    ),
    RouteExecutionFailure.conflict => unifiedSwapText(
      context,
      'review.failure.conflict',
      'Durable route identity conflicts with this Review.',
    ),
    RouteExecutionFailure.networkUnavailable => unifiedSwapText(
      context,
      'review.failure.network',
      'The wallet could not safely start route observation.',
    ),
    RouteExecutionFailure.storageUnavailable => unifiedSwapText(
      context,
      'review.failure.storage',
      'Durable route storage is temporarily unavailable.',
    ),
    RouteExecutionFailure.serviceUnavailable => unifiedSwapText(
      context,
      'review.failure.service',
      'Execution is temporarily unavailable.',
    ),
    RouteExecutionFailure.controlNotAuthorized ||
    RouteExecutionFailure.actionNotAuthorized ||
    RouteExecutionFailure.notFound ||
    RouteExecutionFailure.unknown =>
      failure == null
          ? null
          : unifiedSwapText(
              context,
              'review.failure.unknown',
              'Execution could not start safely.',
            ),
    null => null,
  };
}

String? _announcement(
  BuildContext context,
  RouteLiveAnnouncement announcement,
) => switch (announcement) {
  RouteLiveAnnouncement.none => null,
  RouteLiveAnnouncement.starting => unifiedSwapText(
    context,
    'announcement.starting',
    'Unified Swap execution is starting.',
  ),
  RouteLiveAnnouncement.reattaching => unifiedSwapText(
    context,
    'announcement.reattaching',
    'Reattaching to authoritative Unified Swap status.',
  ),
  RouteLiveAnnouncement.validating => unifiedSwapText(
    context,
    'announcement.validating',
    'Unified Swap route is validating.',
  ),
  RouteLiveAnnouncement.approvalRequired => unifiedSwapText(
    context,
    'announcement.approvalRequired',
    'Unified Swap token approval requires attention.',
  ),
  RouteLiveAnnouncement.sending => unifiedSwapText(
    context,
    'announcement.sending',
    'Unified Swap source funds are sending.',
  ),
  RouteLiveAnnouncement.receiving => unifiedSwapText(
    context,
    'announcement.receiving',
    'Unified Swap destination funds are being received.',
  ),
  RouteLiveAnnouncement.attentionRequired => unifiedSwapText(
    context,
    'announcement.attentionRequired',
    'Unified Swap requires your attention.',
  ),
  RouteLiveAnnouncement.recoveryRequired => unifiedSwapText(
    context,
    'announcement.recoveryRequired',
    'Unified Swap recovery information is available.',
  ),
  RouteLiveAnnouncement.completed => unifiedSwapText(
    context,
    'announcement.completed',
    'Unified Swap completed.',
  ),
  RouteLiveAnnouncement.cancelled => unifiedSwapText(
    context,
    'announcement.cancelled',
    'Unified Swap cancelled.',
  ),
  RouteLiveAnnouncement.failed => unifiedSwapText(
    context,
    'announcement.failed',
    'Unified Swap failed.',
  ),
  RouteLiveAnnouncement.statusUnavailable => unifiedSwapText(
    context,
    'announcement.statusUnavailable',
    'Unified Swap status is unavailable. Controls are disabled.',
  ),
};
