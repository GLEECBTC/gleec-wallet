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
    this.selectionGateway,
    this.recoveryReviewSelector,
    this.initialRouteExecutionId,
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
  final UnifiedSwapSelectionGateway? selectionGateway;
  final UnifiedSwapRecoveryReviewSelector? recoveryReviewSelector;
  final String? initialRouteExecutionId;
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
    if (widget.manageLifecycle) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
        final confirmed = await _confirmExternalRecipient(recovery: true);
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

  Future<void> _onIntentChanged(UnifiedSwapIntent intent) async {
    final quote = _quoteBloc;
    if (quote == null) return;
    final previous = quote.state.intent;
    final recipientContextUnchanged =
        previous != null &&
        intent.recipient == previous.recipient &&
        intent.destination.sameIdentity(previous.destination);
    if (previous == null ||
        recipientContextUnchanged ||
        intent.externalRecipientConfirmed) {
      quote.add(UnifiedSwapIntentChanged(intent));
      return;
    }
    final composition = _productionComposition(context);
    if (composition == null) {
      quote.add(UnifiedSwapIntentChanged(intent));
      return;
    }
    final generation = ++_reviewGeneration;
    final owned = await composition.recipientIsWalletOwned(
      asset: intent.destination,
      address: intent.recipient,
    );
    if (!mounted ||
        generation != _reviewGeneration ||
        quote.state.intent?.revision != previous.revision) {
      return;
    }
    if (owned == null) {
      quote.add(UnifiedSwapIntentChanged(intent));
      return;
    }
    if (owned) {
      quote.add(
        UnifiedSwapIntentChanged(
          intent.copyWith(externalRecipientConfirmed: false),
        ),
      );
      return;
    }
    if (await _confirmExternalRecipient(recovery: false) &&
        mounted &&
        generation == _reviewGeneration &&
        quote.state.intent?.revision == previous.revision) {
      quote.add(
        UnifiedSwapIntentChanged(
          intent.copyWith(externalRecipientConfirmed: true),
        ),
      );
    }
  }

  Future<bool> _confirmExternalRecipient({required bool recovery}) async {
    final result = await showDialog<bool>(
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
        content: Text(
          recovery
              ? unifiedSwapText(
                  dialogContext,
                  'recipient.recoveryBody',
                  'Recovery will use the original external destination '
                      'address. Confirm it again before requesting a fresh '
                      'route.',
                )
              : unifiedSwapText(
                  dialogContext,
                  'recipient.externalBody',
                  'This address is not owned by the active wallet. Confirm the '
                      'destination network and recipient before continuing.',
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
    return result ?? false;
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
          state: quoteState,
          onIntentChanged: (intent) => unawaited(_onIntentChanged(intent)),
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
          selectionGateway:
              widget.selectionGateway ?? _productionComposition(context),
          reviewInFlight: _reviewInFlight,
          reviewFailure: _reviewFailure,
          now: widget.now,
        ),
      );
    }
    return BlocListener<RouteExecutionBloc, RouteExecutionState>(
      bloc: execution,
      listenWhen: (previous, current) =>
          previous.announcement != current.announcement ||
          previous.walletId != current.walletId,
      listener: (context, state) {
        _requestInitialReattach();
        unawaited(_announce(state.announcement));
        final draft = _recoveryDraft;
        if (draft != null && !_recoveryProgressMatches(draft, state.progress)) {
          _cancelRecovery();
        }
      },
      child: BlocBuilder<RouteExecutionBloc, RouteExecutionState>(
        bloc: execution,
        builder: (context, executionState) {
          if (_recoveryDraft case final draft?) {
            return _recoveryBody(
              quote: quote,
              executionState: executionState,
              draft: draft,
            );
          }
          if (executionState.status ==
                  RouteExecutionLoadStatus.reviewRequired &&
              executionState.review != null) {
            final review = executionState.review!;
            return RouteReviewView(
              review: review,
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
              ),
              now: widget.now,
            );
          }
          if (executionState.status != RouteExecutionLoadStatus.idle) {
            return RouteExecutionView(
              state: executionState,
              onReattach: () {
                final routeExecutionId = executionState.routeExecutionId;
                if (routeExecutionId != null) {
                  execution.add(
                    RouteExecutionReattachRequested(routeExecutionId),
                  );
                }
              },
              onCancel: () =>
                  execution.add(const RouteExecutionCancelRequested()),
              onStopAfterCurrent: () => execution.add(
                const RouteExecutionStopAfterCurrentRequested(),
              ),
              onDecision: (kind) => unawaited(_submitDecision(kind)),
              canSelectRecoveryRoute:
                  widget.recoveryReviewSelector != null ||
                  (_productionComposition(context) != null &&
                      widget.config.canExecute),
              clipboardWriter: widget.clipboardWriter,
              announcement: widget.announcement,
            );
          }
          return BlocBuilder<UnifiedSwapBloc, UnifiedSwapState>(
            bloc: quote,
            builder: (context, quoteState) => UnifiedSwapEntryView(
              state: quoteState,
              onIntentChanged: (intent) => unawaited(_onIntentChanged(intent)),
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
              selectionGateway:
                  widget.selectionGateway ?? _productionComposition(context),
              reviewInFlight: _reviewInFlight,
              reviewFailure: _reviewFailure,
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
                onIntentChanged: (intent) =>
                    unawaited(_onIntentChanged(intent)),
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
) => switch (failure) {
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
