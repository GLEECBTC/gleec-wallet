import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_acceptance_coordinator.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_repository.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';

sealed class RouteExecutionEvent extends Equatable {
  const RouteExecutionEvent();

  @override
  List<Object?> get props => const [];
}

final class RouteExecutionWalletChanged extends RouteExecutionEvent {
  const RouteExecutionWalletChanged(this.walletId);

  final String? walletId;

  @override
  List<Object?> get props => [walletId];
}

final class RouteExecutionReviewPresented extends RouteExecutionEvent {
  const RouteExecutionReviewPresented(this.review);

  final RouteExecutionReview review;

  @override
  List<Object?> get props => [review];
}

/// Discards a prepared Review before execution starts.
///
/// Once acceptance has begun the one-shot consent may already be in use, so
/// this event deliberately becomes inert outside [RouteExecutionLoadStatus.reviewRequired].
final class RouteExecutionReviewDismissed extends RouteExecutionEvent {
  const RouteExecutionReviewDismissed();
}

final class RouteExecutionReviewAccepted extends RouteExecutionEvent {
  const RouteExecutionReviewAccepted({
    required this.reviewId,
    required this.consentDigest,
  });

  final String reviewId;
  final String consentDigest;

  @override
  List<Object?> get props => [reviewId, consentDigest];
}

final class RouteExecutionReattachRequested extends RouteExecutionEvent {
  const RouteExecutionReattachRequested(this.routeExecutionId);

  final String routeExecutionId;

  @override
  List<Object?> get props => [routeExecutionId];
}

final class RouteExecutionAppResumed extends RouteExecutionEvent {
  const RouteExecutionAppResumed();
}

final class RouteExecutionControlTarget extends Equatable {
  const RouteExecutionControlTarget({
    required this.walletId,
    required this.walletGeneration,
    required this.routeExecutionId,
    required this.expectedStateRevision,
  });

  final String walletId;
  final int walletGeneration;
  final String routeExecutionId;
  final int expectedStateRevision;

  @override
  List<Object?> get props => [
    walletId,
    walletGeneration,
    routeExecutionId,
    expectedStateRevision,
  ];
}

final class RouteExecutionCancelRequested extends RouteExecutionEvent {
  const RouteExecutionCancelRequested(this.target);

  final RouteExecutionControlTarget target;

  @override
  List<Object?> get props => [target];
}

final class RouteExecutionStopAfterCurrentRequested
    extends RouteExecutionEvent {
  const RouteExecutionStopAfterCurrentRequested(this.target);

  final RouteExecutionControlTarget target;

  @override
  List<Object?> get props => [target];
}

final class RouteExecutionDecisionSubmitted extends RouteExecutionEvent {
  const RouteExecutionDecisionSubmitted(this.decision);

  final RouteExecutionDecision decision;

  @override
  List<Object?> get props => [decision];
}

final class _RouteExecutionProgressReceived extends RouteExecutionEvent {
  const _RouteExecutionProgressReceived({
    required this.generation,
    required this.progress,
  });

  final int generation;
  final RouteExecutionProgress progress;

  @override
  List<Object?> get props => [generation, progress];
}

final class _RouteExecutionObservationFailed extends RouteExecutionEvent {
  const _RouteExecutionObservationFailed({
    required this.generation,
    required this.failure,
  });

  final int generation;
  final RouteExecutionFailure failure;

  @override
  List<Object?> get props => [generation, failure];
}

final class _RouteExecutionObservationEnded extends RouteExecutionEvent {
  const _RouteExecutionObservationEnded({required this.generation});

  final int generation;

  @override
  List<Object?> get props => [generation];
}

enum RouteExecutionLoadStatus {
  idle,
  reviewRequired,
  starting,
  reattaching,
  observing,
  attentionRequired,
  recovery,
  completed,
  cancelled,
  failed,
  unknown,
}

enum RouteReviewRefreshStatus { none, materialChange, latestTermsUnavailable }

class RouteExecutionFreshQuote extends Equatable {
  const RouteExecutionFreshQuote({
    required this.intent,
    required this.evaluation,
  });

  final UnifiedSwapIntent intent;
  final UnifiedSwapQuoteEvaluation evaluation;

  @override
  List<Object?> get props => [intent, evaluation];
}

class RouteExecutionState extends Equatable {
  const RouteExecutionState({
    this.walletId,
    this.walletGeneration = 0,
    this.status = RouteExecutionLoadStatus.idle,
    this.review,
    this.session,
    this.progress,
    this.controlInFlight = false,
    this.failure,
    this.announcement = RouteLiveAnnouncement.none,
    this.reviewRefreshStatus = RouteReviewRefreshStatus.none,
    this.freshQuote,
    this.previousReview,
  });

  final String? walletId;
  final int walletGeneration;
  final RouteExecutionLoadStatus status;
  final RouteExecutionReview? review;
  final RouteExecutionSession? session;
  final RouteExecutionProgress? progress;
  final bool controlInFlight;
  final RouteExecutionFailure? failure;
  final RouteLiveAnnouncement announcement;
  final RouteReviewRefreshStatus reviewRefreshStatus;
  final RouteExecutionFreshQuote? freshQuote;
  final RouteExecutionReview? previousReview;

  String? get routeExecutionId =>
      session?.routeExecutionId ?? review?.routeExecutionId;

  RouteExecutionControlTarget? get controlTarget {
    final walletId = this.walletId;
    final session = this.session;
    final progress = this.progress;
    if (walletId == null ||
        session == null ||
        progress == null ||
        session.routeExecutionId != progress.routeExecutionId ||
        !progress.isExecutable) {
      return null;
    }
    return RouteExecutionControlTarget(
      walletId: walletId,
      walletGeneration: walletGeneration,
      routeExecutionId: progress.routeExecutionId,
      expectedStateRevision: progress.stateRevision,
    );
  }

  RouteExecutionState copyWith({
    String? walletId,
    bool clearWalletId = false,
    int? walletGeneration,
    RouteExecutionLoadStatus? status,
    RouteExecutionReview? review,
    bool clearReview = false,
    RouteExecutionSession? session,
    bool clearSession = false,
    RouteExecutionProgress? progress,
    bool clearProgress = false,
    bool? controlInFlight,
    RouteExecutionFailure? failure,
    bool clearFailure = false,
    RouteLiveAnnouncement? announcement,
    RouteReviewRefreshStatus? reviewRefreshStatus,
    RouteExecutionFreshQuote? freshQuote,
    bool clearFreshQuote = false,
    RouteExecutionReview? previousReview,
    bool clearPreviousReview = false,
  }) {
    return RouteExecutionState(
      walletId: clearWalletId ? null : walletId ?? this.walletId,
      walletGeneration: walletGeneration ?? this.walletGeneration,
      status: status ?? this.status,
      review: clearReview ? null : review ?? this.review,
      session: clearSession ? null : session ?? this.session,
      progress: clearProgress ? null : progress ?? this.progress,
      controlInFlight: controlInFlight ?? this.controlInFlight,
      failure: clearFailure ? null : failure ?? this.failure,
      announcement: announcement ?? this.announcement,
      reviewRefreshStatus: reviewRefreshStatus ?? this.reviewRefreshStatus,
      freshQuote: clearFreshQuote ? null : freshQuote ?? this.freshQuote,
      previousReview: clearPreviousReview
          ? null
          : previousReview ?? this.previousReview,
    );
  }

  @override
  List<Object?> get props => [
    walletId,
    walletGeneration,
    status,
    review,
    session,
    progress,
    controlInFlight,
    failure,
    announcement,
    reviewRefreshStatus,
    freshQuote,
    previousReview,
  ];
}

class RouteExecutionBloc
    extends Bloc<RouteExecutionEvent, RouteExecutionState> {
  RouteExecutionBloc({
    required RouteExecutionRepository repository,
    RouteExecutionAcceptanceCoordinator? acceptanceCoordinator,
    DateTime Function()? now,
    RouteExecutionState initialState = const RouteExecutionState(),
  }) : _repository = repository,
       _acceptanceCoordinator = acceptanceCoordinator,
       _now = now ?? (() => DateTime.now().toUtc()),
       _latestAcceptedProgress = initialState.progress,
       super(initialState) {
    on<RouteExecutionWalletChanged>(_onWalletChanged);
    on<RouteExecutionReviewPresented>(_onReviewPresented);
    on<RouteExecutionReviewDismissed>(_onReviewDismissed);
    on<RouteExecutionReviewAccepted>(
      _onReviewAccepted,
      transformer: droppable(),
    );
    on<RouteExecutionReattachRequested>(
      _onReattachRequested,
      transformer: droppable(),
    );
    on<RouteExecutionAppResumed>(_onAppResumed, transformer: droppable());
    on<RouteExecutionCancelRequested>(
      _onCancelRequested,
      transformer: droppable(),
    );
    on<RouteExecutionStopAfterCurrentRequested>(
      _onStopAfterCurrentRequested,
      transformer: droppable(),
    );
    on<RouteExecutionDecisionSubmitted>(
      _onDecisionSubmitted,
      transformer: droppable(),
    );
    on<_RouteExecutionProgressReceived>(_onProgressReceived);
    on<_RouteExecutionObservationFailed>(_onObservationFailed);
    on<_RouteExecutionObservationEnded>(_onObservationEnded);
  }

  final RouteExecutionRepository _repository;
  final RouteExecutionAcceptanceCoordinator? _acceptanceCoordinator;
  final DateTime Function() _now;
  StreamSubscription<RouteExecutionProgress>? _observation;
  int _scopeGeneration = 0;
  int _sessionGeneration = 0;
  int _commandGeneration = 0;
  bool _observationReconciliationAttempted = false;
  bool _commandInFlight = false;
  int? _commandAwaitingProgressGeneration;
  RouteExecutionProgress? _latestAcceptedProgress;

  Future<void> _onWalletChanged(
    RouteExecutionWalletChanged event,
    Emitter<RouteExecutionState> emit,
  ) async {
    _scopeGeneration++;
    _sessionGeneration++;
    _commandGeneration++;
    _observationReconciliationAttempted = false;
    _commandInFlight = false;
    _commandAwaitingProgressGeneration = null;
    _latestAcceptedProgress = null;
    final observation = _observation;
    _observation = null;
    emit(
      RouteExecutionState(
        walletId: event.walletId,
        walletGeneration: _scopeGeneration,
      ),
    );
    await observation?.cancel();
  }

  void _onReviewPresented(
    RouteExecutionReviewPresented event,
    Emitter<RouteExecutionState> emit,
  ) {
    final walletId = state.walletId;
    if (walletId == null || event.review.walletId != walletId) {
      emit(
        state.copyWith(
          failure: RouteExecutionFailure.invalidReview,
          announcement: RouteLiveAnnouncement.statusUnavailable,
        ),
      );
      return;
    }
    if (_hasActiveExecution(state.status) || _hasUnresolvedSession) {
      return;
    }
    _sessionGeneration++;
    _latestAcceptedProgress = null;
    final observation = _observation;
    _observation = null;
    unawaited(observation?.cancel());
    emit(
      state.copyWith(
        status: RouteExecutionLoadStatus.reviewRequired,
        review: event.review,
        clearSession: true,
        clearProgress: true,
        controlInFlight: false,
        clearFailure: true,
        announcement: RouteLiveAnnouncement.none,
        reviewRefreshStatus: RouteReviewRefreshStatus.none,
        clearFreshQuote: true,
        clearPreviousReview: true,
      ),
    );
  }

  void _onReviewDismissed(
    RouteExecutionReviewDismissed event,
    Emitter<RouteExecutionState> emit,
  ) {
    if (state.status != RouteExecutionLoadStatus.reviewRequired) return;
    _sessionGeneration++;
    _latestAcceptedProgress = null;
    final observation = _observation;
    _observation = null;
    unawaited(observation?.cancel());
    emit(
      state.copyWith(
        status: RouteExecutionLoadStatus.idle,
        clearReview: true,
        clearSession: true,
        clearProgress: true,
        controlInFlight: false,
        clearFailure: true,
        announcement: RouteLiveAnnouncement.none,
        reviewRefreshStatus: RouteReviewRefreshStatus.none,
        clearFreshQuote: true,
        clearPreviousReview: true,
      ),
    );
  }

  Future<void> _onReviewAccepted(
    RouteExecutionReviewAccepted event,
    Emitter<RouteExecutionState> emit,
  ) async {
    final consentedReview = state.review;
    final walletId = state.walletId;
    if (walletId == null ||
        consentedReview == null ||
        state.status != RouteExecutionLoadStatus.reviewRequired ||
        event.reviewId != consentedReview.reviewId ||
        event.consentDigest != consentedReview.consentDigest ||
        !consentedReview.isExecutable) {
      emit(
        state.copyWith(
          failure: RouteExecutionFailure.invalidReview,
          announcement: RouteLiveAnnouncement.statusUnavailable,
        ),
      );
      return;
    }
    if (consentedReview.isExpiredAt(_now())) {
      emit(
        state.copyWith(
          failure: RouteExecutionFailure.reviewExpired,
          announcement: RouteLiveAnnouncement.statusUnavailable,
        ),
      );
      return;
    }
    final acceptanceCoordinator = _acceptanceCoordinator;
    if (acceptanceCoordinator == null) {
      _emitPreInitFailure(RouteExecutionFailure.capabilityUnavailable, emit);
      return;
    }

    final scopeGeneration = _scopeGeneration;
    final sessionGeneration = ++_sessionGeneration;
    emit(
      state.copyWith(
        status: RouteExecutionLoadStatus.starting,
        controlInFlight: false,
        clearFailure: true,
        announcement: RouteLiveAnnouncement.none,
        reviewRefreshStatus: RouteReviewRefreshStatus.none,
        clearFreshQuote: true,
        clearPreviousReview: true,
      ),
    );

    late final RouteExecutionAcceptanceResult acceptance;
    try {
      acceptance = await acceptanceCoordinator.revalidate(consentedReview);
    } on RouteExecutionException catch (error) {
      if (_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        _emitPreInitFailure(error.failure, emit);
      }
      return;
    } on Object {
      if (_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        _emitPreInitFailure(RouteExecutionFailure.unknown, emit);
      }
      return;
    }
    if (!_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
      _abandonAcceptanceReplacement(acceptanceCoordinator, acceptance);
      return;
    }

    late final RouteExecutionReview review;
    try {
      switch (acceptance) {
        case RouteExecutionAcceptanceQuiet(
          review: final acceptedReview,
          transactionId: final transactionId,
        ):
          review = _commitAcceptanceReplacement(
            coordinator: acceptanceCoordinator,
            transactionId: transactionId,
            consentedReview: consentedReview,
            proposedReview: acceptedReview,
          );
          emit(
            state.copyWith(
              status: RouteExecutionLoadStatus.starting,
              review: review,
              clearFailure: true,
              announcement: RouteLiveAnnouncement.starting,
              reviewRefreshStatus: RouteReviewRefreshStatus.none,
            ),
          );
        case RouteExecutionAcceptanceMaterialChange(
          consentedReview: final priorReview,
          replacementReview: final replacement,
          transactionId: final transactionId,
        ):
          if (priorReview != consentedReview) {
            _abandonReplacement(acceptanceCoordinator, transactionId);
            throw const RouteExecutionException(
              RouteExecutionFailure.invalidReview,
            );
          }
          final committedReplacement = _commitAcceptanceReplacement(
            coordinator: acceptanceCoordinator,
            transactionId: transactionId,
            consentedReview: consentedReview,
            proposedReview: replacement,
          );
          emit(
            state.copyWith(
              status: RouteExecutionLoadStatus.reviewRequired,
              review: committedReplacement,
              clearSession: true,
              clearProgress: true,
              controlInFlight: false,
              clearFailure: true,
              announcement: RouteLiveAnnouncement.none,
              reviewRefreshStatus: RouteReviewRefreshStatus.materialChange,
              previousReview: priorReview,
            ),
          );
          return;
        case RouteExecutionAcceptanceFreshQuote(
          :final intent,
          :final evaluation,
        ):
          emit(
            state.copyWith(
              status: RouteExecutionLoadStatus.idle,
              clearReview: true,
              clearSession: true,
              clearProgress: true,
              controlInFlight: false,
              clearFailure: true,
              announcement: RouteLiveAnnouncement.none,
              reviewRefreshStatus: RouteReviewRefreshStatus.none,
              freshQuote: RouteExecutionFreshQuote(
                intent: intent,
                evaluation: evaluation,
              ),
              clearPreviousReview: true,
            ),
          );
          return;
        case RouteExecutionAcceptanceUnavailable(:final failure):
          _emitPreInitFailure(failure, emit);
          return;
      }
    } on RouteExecutionException catch (error) {
      _emitPreInitFailure(error.failure, emit);
      return;
    } on Object {
      _emitPreInitFailure(RouteExecutionFailure.unknown, emit);
      return;
    }

    try {
      final session = await _repository.initReviewedExecution(
        walletId: walletId,
        routeExecutionId: review.routeExecutionId,
        reviewId: review.reviewId,
        consentDigest: review.consentDigest,
      );
      _retireConsumedReview(review);
      if (!_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        return;
      }
      if (session.routeExecutionId != review.routeExecutionId) {
        await _handleUncertainInitFailure(
          walletId: walletId,
          routeExecutionId: review.routeExecutionId,
          scopeGeneration: scopeGeneration,
          sessionGeneration: sessionGeneration,
          failure: RouteExecutionFailure.conflict,
          initWasAttempted: true,
          emit: emit,
        );
        return;
      }
      await _observeSession(session, sessionGeneration, emit);
    } on RouteExecutionUncertainInitException catch (error) {
      _retireConsumedReview(review);
      await _handleUncertainInitFailure(
        walletId: walletId,
        routeExecutionId: review.routeExecutionId,
        scopeGeneration: scopeGeneration,
        sessionGeneration: sessionGeneration,
        failure: error.failure,
        initWasAttempted: true,
        emit: emit,
      );
    } on RouteExecutionException catch (error) {
      await _handleUncertainInitFailure(
        walletId: walletId,
        routeExecutionId: review.routeExecutionId,
        scopeGeneration: scopeGeneration,
        sessionGeneration: sessionGeneration,
        failure: error.failure,
        initWasAttempted: false,
        emit: emit,
      );
    } on Object {
      _retireConsumedReview(review);
      await _handleUncertainInitFailure(
        walletId: walletId,
        routeExecutionId: review.routeExecutionId,
        scopeGeneration: scopeGeneration,
        sessionGeneration: sessionGeneration,
        failure: RouteExecutionFailure.unknown,
        initWasAttempted: true,
        emit: emit,
      );
    }
  }

  RouteExecutionReview _commitAcceptanceReplacement({
    required RouteExecutionAcceptanceCoordinator coordinator,
    required String transactionId,
    required RouteExecutionReview consentedReview,
    required RouteExecutionReview proposedReview,
  }) {
    final RouteExecutionAcceptanceTransactionCoordinator?
    transactionCoordinator =
        coordinator is RouteExecutionAcceptanceTransactionCoordinator
        ? coordinator as RouteExecutionAcceptanceTransactionCoordinator
        : null;
    if (transactionCoordinator == null || transactionId.trim().isEmpty) {
      _abandonReplacement(coordinator, transactionId);
      throw const RouteExecutionException(RouteExecutionFailure.invalidReview);
    }
    if (!isValidRouteExecutionReplacement(
      consented: consentedReview,
      replacement: proposedReview,
      now: _now(),
    )) {
      transactionCoordinator.abandonReplacement(transactionId);
      throw const RouteExecutionException(RouteExecutionFailure.invalidReview);
    }
    return transactionCoordinator.commitReplacement(
      transactionId: transactionId,
      expectedReview: consentedReview,
      proposedReview: proposedReview,
    );
  }

  void _abandonAcceptanceReplacement(
    RouteExecutionAcceptanceCoordinator coordinator,
    RouteExecutionAcceptanceResult acceptance,
  ) {
    final transactionId = switch (acceptance) {
      RouteExecutionAcceptanceQuiet(:final transactionId) => transactionId,
      RouteExecutionAcceptanceMaterialChange(:final transactionId) =>
        transactionId,
      RouteExecutionAcceptanceFreshQuote() ||
      RouteExecutionAcceptanceUnavailable() => null,
    };
    if (transactionId != null) {
      _abandonReplacement(coordinator, transactionId);
    }
  }

  void _abandonReplacement(
    RouteExecutionAcceptanceCoordinator coordinator,
    String transactionId,
  ) {
    if (coordinator
        case final RouteExecutionAcceptanceTransactionCoordinator
            transactionCoordinator) {
      transactionCoordinator.abandonReplacement(transactionId);
    }
  }

  void _retireConsumedReview(RouteExecutionReview review) {
    switch (_acceptanceCoordinator) {
      case final RouteExecutionAcceptanceLifecycle lifecycle:
        lifecycle.retireConsumedReview(review);
      case _:
        break;
    }
  }

  Future<void> _handleUncertainInitFailure({
    required String walletId,
    required String routeExecutionId,
    required int scopeGeneration,
    required int sessionGeneration,
    required RouteExecutionFailure failure,
    required bool initWasAttempted,
    required Emitter<RouteExecutionState> emit,
  }) async {
    if (!_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) return;
    if (!initWasAttempted && !_requiresDurableInitReconciliation(failure)) {
      _emitPreInitFailure(failure, emit);
      return;
    }

    emit(
      state.copyWith(
        status: RouteExecutionLoadStatus.reattaching,
        controlInFlight: _commandInFlight,
        clearFailure: true,
        announcement: RouteLiveAnnouncement.reattaching,
      ),
    );
    try {
      final session = await _repository.reattachExecution(
        walletId: walletId,
        routeExecutionId: routeExecutionId,
      );
      if (!_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        return;
      }
      if (session.routeExecutionId != routeExecutionId) {
        _emitUnknownFailure(RouteExecutionFailure.conflict, emit);
        return;
      }
      await _observeSession(session, sessionGeneration, emit);
    } on Object {
      if (_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        // Fresh consent is one-shot. If init acknowledgement is uncertain and
        // KDF cannot yet reattach, never retry init or claim that execution
        // failed; preserve the original typed uncertainty for reconciliation.
        _emitUnknownFailure(failure, emit);
      }
    }
  }

  Future<void> _onReattachRequested(
    RouteExecutionReattachRequested event,
    Emitter<RouteExecutionState> emit,
  ) async {
    if ((_commandInFlight && _commandAwaitingProgressGeneration == null) ||
        _reattachWouldInterruptStart(state.status) ||
        _wouldReplaceNonterminalSession(event.routeExecutionId)) {
      return;
    }
    await _reattach(event.routeExecutionId, emit);
  }

  bool _wouldReplaceNonterminalSession(String routeExecutionId) {
    final session = state.session;
    if (session == null || session.routeExecutionId == routeExecutionId) {
      return false;
    }
    final progress = state.progress;
    if (progress == null ||
        progress.routeExecutionId != session.routeExecutionId) {
      return true;
    }
    return progress.outcome != RouteExecutionOutcome.completed &&
        progress.outcome != RouteExecutionOutcome.cancelled &&
        progress.outcome != RouteExecutionOutcome.failed;
  }

  Future<void> _onAppResumed(
    RouteExecutionAppResumed event,
    Emitter<RouteExecutionState> emit,
  ) async {
    if ((_commandInFlight && _commandAwaitingProgressGeneration == null) ||
        _reattachWouldInterruptStart(state.status)) {
      return;
    }
    final routeExecutionId = state.routeExecutionId;
    if (routeExecutionId != null) await _reattach(routeExecutionId, emit);
  }

  Future<void> _reattach(
    String routeExecutionId,
    Emitter<RouteExecutionState> emit,
  ) async {
    final walletId = state.walletId;
    if (walletId == null ||
        routeExecutionId.trim().isEmpty ||
        (_commandInFlight && _commandAwaitingProgressGeneration == null) ||
        _reattachWouldInterruptStart(state.status)) {
      return;
    }
    final scopeGeneration = _scopeGeneration;
    final sessionGeneration = ++_sessionGeneration;
    emit(
      state.copyWith(
        status: RouteExecutionLoadStatus.reattaching,
        controlInFlight: _commandInFlight,
        clearFailure: true,
        announcement: RouteLiveAnnouncement.reattaching,
      ),
    );
    try {
      final session = await _repository.reattachExecution(
        walletId: walletId,
        routeExecutionId: routeExecutionId,
      );
      if (!_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        return;
      }
      if (session.routeExecutionId != routeExecutionId) {
        _emitFailure(RouteExecutionFailure.conflict, emit);
        return;
      }
      await _observeSession(session, sessionGeneration, emit);
    } on RouteExecutionException catch (error) {
      if (_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        // A failed status read does not prove that durable execution failed.
        // Keep the route in reconciliation instead of presenting a terminal
        // failure that could permit another review over an active route.
        _emitUnknownFailure(error.failure, emit);
      }
    } on Object {
      if (_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        _emitUnknownFailure(RouteExecutionFailure.unknown, emit);
      }
    }
  }

  bool get _hasUnresolvedSession {
    if (_commandInFlight) return true;
    final session = state.session;
    if (session == null) return false;
    final progress = _latestAcceptedProgress;
    return progress == null ||
        progress.routeExecutionId != session.routeExecutionId ||
        !_isTerminalOutcome(progress.outcome);
  }

  Future<void> _observeSession(
    RouteExecutionSession session,
    int generation,
    Emitter<RouteExecutionState> emit, {
    bool resetReconciliationGuard = true,
  }) async {
    await _observation?.cancel();
    if (emit.isDone || generation != _sessionGeneration) return;
    final retainedProgress = _latestAcceptedProgress;
    final isSameRoute =
        retainedProgress?.routeExecutionId == session.routeExecutionId;
    if (!isSameRoute) {
      _latestAcceptedProgress = null;
    }
    if (resetReconciliationGuard) {
      _observationReconciliationAttempted = false;
    }
    emit(
      state.copyWith(
        status: retainedProgress == null || !isSameRoute
            ? RouteExecutionLoadStatus.observing
            : _statusFor(retainedProgress),
        session: session,
        progress: isSameRoute ? retainedProgress : null,
        clearProgress: !isSameRoute,
        controlInFlight: _commandInFlight,
        clearFailure: true,
      ),
    );
    _observation = _repository
        .observe(session)
        .listen(
          (progress) => add(
            _RouteExecutionProgressReceived(
              generation: generation,
              progress: progress,
            ),
          ),
          onError: (Object error) => add(
            _RouteExecutionObservationFailed(
              generation: generation,
              failure: _observationFailure(error),
            ),
          ),
          onDone: () => Timer.run(() {
            if (!isClosed) {
              add(_RouteExecutionObservationEnded(generation: generation));
            }
          }),
        );
  }

  void _onObservationEnded(
    _RouteExecutionObservationEnded event,
    Emitter<RouteExecutionState> emit,
  ) {
    if (event.generation != _sessionGeneration) return;
    final progress = _latestAcceptedProgress;
    if (progress != null && _isTerminalOutcome(progress.outcome)) return;
    add(
      _RouteExecutionObservationFailed(
        generation: event.generation,
        failure: RouteExecutionFailure.serviceUnavailable,
      ),
    );
  }

  void _onProgressReceived(
    _RouteExecutionProgressReceived event,
    Emitter<RouteExecutionState> emit,
  ) {
    final session = state.session;
    if (event.generation != _sessionGeneration ||
        session == null ||
        event.progress.routeExecutionId != session.routeExecutionId) {
      return;
    }
    final previous = _latestAcceptedProgress;
    if (previous != null) {
      if (event.progress.stateRevision < previous.stateRevision) return;
      if (event.progress.stateRevision == previous.stateRevision) {
        if (event.progress != previous) {
          add(
            _RouteExecutionObservationFailed(
              generation: event.generation,
              failure: RouteExecutionFailure.conflict,
            ),
          );
        } else if (_finishCommandAwaitingProgress()) {
          emit(state.copyWith(controlInFlight: false, clearFailure: true));
        }
        return;
      }
      if (!_canAdvanceProgress(previous, event.progress)) {
        add(
          _RouteExecutionObservationFailed(
            generation: event.generation,
            failure: RouteExecutionFailure.conflict,
          ),
        );
        return;
      }
    }
    _finishCommandAwaitingProgress();
    _latestAcceptedProgress = event.progress;
    emit(
      state.copyWith(
        status: _statusFor(event.progress),
        progress: event.progress,
        controlInFlight: _commandInFlight,
        clearFailure: true,
        announcement: event.progress.announcement,
      ),
    );
  }

  Future<void> _onObservationFailed(
    _RouteExecutionObservationFailed event,
    Emitter<RouteExecutionState> emit,
  ) async {
    if (event.generation != _sessionGeneration) return;
    final walletId = state.walletId;
    final session = state.session;
    if (walletId == null || session == null) {
      _emitUnknownFailure(event.failure, emit);
      return;
    }
    if (_observationReconciliationAttempted) {
      _emitUnknownFailure(event.failure, emit);
      return;
    }

    _observationReconciliationAttempted = true;
    final scopeGeneration = _scopeGeneration;
    final sessionGeneration = ++_sessionGeneration;
    await _observation?.cancel();
    _observation = null;
    emit(
      state.copyWith(
        status: RouteExecutionLoadStatus.reattaching,
        controlInFlight: _commandInFlight,
        failure: event.failure,
        announcement: RouteLiveAnnouncement.reattaching,
      ),
    );
    try {
      final attached = await _repository.reattachExecution(
        walletId: walletId,
        routeExecutionId: session.routeExecutionId,
      );
      if (!_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        return;
      }
      if (attached.routeExecutionId != session.routeExecutionId) {
        _emitUnknownFailure(RouteExecutionFailure.conflict, emit);
        return;
      }
      await _observeSession(
        attached,
        sessionGeneration,
        emit,
        resetReconciliationGuard: false,
      );
    } on Object {
      if (_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        _emitUnknownFailure(event.failure, emit);
      }
    }
  }

  Future<void> _onCancelRequested(
    RouteExecutionCancelRequested event,
    Emitter<RouteExecutionState> emit,
  ) async {
    if (_commandInFlight) return;
    final progress = state.progress;
    if (!_matchesControlTarget(event.target, progress) ||
        !_canControl(progress) ||
        !progress!.controls.canCancel ||
        progress.controls.reconciliationOnly) {
      _emitControlDenied(emit);
      return;
    }
    await _runControl(
      emit,
      (walletId, routeExecutionId) => _repository.cancelExecution(
        walletId: walletId,
        routeExecutionId: routeExecutionId,
      ),
    );
  }

  Future<void> _onStopAfterCurrentRequested(
    RouteExecutionStopAfterCurrentRequested event,
    Emitter<RouteExecutionState> emit,
  ) async {
    if (_commandInFlight) return;
    final progress = state.progress;
    if (!_matchesControlTarget(event.target, progress) ||
        !_canControl(progress) ||
        !progress!.controls.canStopAfterCurrent ||
        progress.controls.reconciliationOnly) {
      _emitControlDenied(emit);
      return;
    }
    await _runControl(
      emit,
      (walletId, routeExecutionId) => _repository.stopAfterCurrent(
        walletId: walletId,
        routeExecutionId: routeExecutionId,
      ),
    );
  }

  bool _matchesControlTarget(
    RouteExecutionControlTarget target,
    RouteExecutionProgress? progress,
  ) =>
      state.walletId == target.walletId &&
      state.walletGeneration == target.walletGeneration &&
      state.session?.routeExecutionId == target.routeExecutionId &&
      progress?.routeExecutionId == target.routeExecutionId &&
      progress?.stateRevision == target.expectedStateRevision;

  Future<void> _onDecisionSubmitted(
    RouteExecutionDecisionSubmitted event,
    Emitter<RouteExecutionState> emit,
  ) async {
    if (_commandInFlight) return;
    final walletId = state.walletId;
    final session = state.session;
    final progress = state.progress;
    final pending = progress?.pendingAction;
    if (walletId == null ||
        session == null ||
        progress == null ||
        !progress.isExecutable ||
        pending == null ||
        !pending.isExecutable ||
        event.decision.kind == RouteExecutionActionKind.unknown ||
        event.decision.actionId != pending.actionId ||
        event.decision.expectedStateRevision != progress.stateRevision ||
        !pending.allowedActions.contains(event.decision.kind) ||
        (event.decision.kind == RouteExecutionActionKind.acceptReplacement &&
            (event.decision.replacementProposalDigest == null ||
                event.decision.replacementProposalDigest !=
                    pending.replacementProposal?.proposalDigest)) ||
        (event.decision.kind == RouteExecutionActionKind.selectRecoveryRoute &&
            (event.decision.recoveryReviewId == null ||
                event.decision.recoveryReviewId!.trim().isEmpty))) {
      emit(
        state.copyWith(
          failure: RouteExecutionFailure.actionNotAuthorized,
          announcement: RouteLiveAnnouncement.statusUnavailable,
        ),
      );
      return;
    }

    final scopeGeneration = _scopeGeneration;
    final commandGeneration = ++_commandGeneration;
    _commandInFlight = true;
    emit(state.copyWith(controlInFlight: true, clearFailure: true));
    try {
      final acknowledgement = await _repository.submitDecision(
        walletId: walletId,
        session: session,
        decision: event.decision,
      );
      if (_isCurrentCommand(
        walletId: walletId,
        routeExecutionId: session.routeExecutionId,
        scopeGeneration: scopeGeneration,
        commandGeneration: commandGeneration,
        emit: emit,
      )) {
        if (!acknowledgement.wasDelivered) {
          await _reconcileUncertainCommand(
            walletId: walletId,
            routeExecutionId: session.routeExecutionId,
            scopeGeneration: scopeGeneration,
            commandGeneration: commandGeneration,
            failure: RouteExecutionFailure.serviceUnavailable,
            emit: emit,
          );
          return;
        }
        _finishCommand(commandGeneration);
        emit(state.copyWith(controlInFlight: false, clearFailure: true));
      }
    } on RouteExecutionUncertainDecisionException catch (error) {
      await _reconcileUncertainCommand(
        walletId: walletId,
        routeExecutionId: session.routeExecutionId,
        scopeGeneration: scopeGeneration,
        commandGeneration: commandGeneration,
        failure: error.failure,
        emit: emit,
      );
    } on RouteExecutionException catch (error) {
      if (_isCurrentCommand(
        walletId: walletId,
        routeExecutionId: session.routeExecutionId,
        scopeGeneration: scopeGeneration,
        commandGeneration: commandGeneration,
        emit: emit,
      )) {
        _finishCommand(commandGeneration);
        emit(state.copyWith(controlInFlight: false, failure: error.failure));
      }
    } on Object {
      await _reconcileUncertainCommand(
        walletId: walletId,
        routeExecutionId: session.routeExecutionId,
        scopeGeneration: scopeGeneration,
        commandGeneration: commandGeneration,
        failure: RouteExecutionFailure.unknown,
        emit: emit,
      );
    }
  }

  bool _canControl(RouteExecutionProgress? progress) =>
      state.walletId != null &&
      state.session != null &&
      progress != null &&
      progress.isExecutable &&
      !state.controlInFlight &&
      !_commandInFlight;

  Future<void> _runControl(
    Emitter<RouteExecutionState> emit,
    Future<void> Function(String walletId, String routeExecutionId) control,
  ) async {
    if (_commandInFlight) return;
    final walletId = state.walletId!;
    final routeExecutionId = state.session!.routeExecutionId;
    final scopeGeneration = _scopeGeneration;
    final commandGeneration = ++_commandGeneration;
    _commandInFlight = true;
    emit(state.copyWith(controlInFlight: true, clearFailure: true));
    try {
      await control(walletId, routeExecutionId);
      if (_isCurrentCommand(
        walletId: walletId,
        routeExecutionId: routeExecutionId,
        scopeGeneration: scopeGeneration,
        commandGeneration: commandGeneration,
        emit: emit,
      )) {
        _finishCommand(commandGeneration);
        emit(state.copyWith(controlInFlight: false, clearFailure: true));
      }
    } on RouteExecutionUncertainControlException catch (error) {
      await _reconcileUncertainCommand(
        walletId: walletId,
        routeExecutionId: routeExecutionId,
        scopeGeneration: scopeGeneration,
        commandGeneration: commandGeneration,
        failure: error.failure,
        emit: emit,
      );
    } on RouteExecutionException catch (error) {
      if (_isCurrentCommand(
        walletId: walletId,
        routeExecutionId: routeExecutionId,
        scopeGeneration: scopeGeneration,
        commandGeneration: commandGeneration,
        emit: emit,
      )) {
        _finishCommand(commandGeneration);
        emit(state.copyWith(controlInFlight: false, failure: error.failure));
      }
    } on Object {
      await _reconcileUncertainCommand(
        walletId: walletId,
        routeExecutionId: routeExecutionId,
        scopeGeneration: scopeGeneration,
        commandGeneration: commandGeneration,
        failure: RouteExecutionFailure.unknown,
        emit: emit,
      );
    }
  }

  Future<void> _reconcileUncertainCommand({
    required String walletId,
    required String routeExecutionId,
    required int scopeGeneration,
    required int commandGeneration,
    required RouteExecutionFailure failure,
    required Emitter<RouteExecutionState> emit,
  }) async {
    if (!_isCurrentCommand(
      walletId: walletId,
      routeExecutionId: routeExecutionId,
      scopeGeneration: scopeGeneration,
      commandGeneration: commandGeneration,
      emit: emit,
    )) {
      return;
    }
    // From this point the original command may have reached KDF. Keep the UI
    // locked until a durable snapshot is observed, even if this first
    // reattach attempt fails. Manual/app-resume reattach remains available.
    _commandAwaitingProgressGeneration = commandGeneration;
    final reconciliationGeneration = ++_sessionGeneration;
    await _observation?.cancel();
    _observation = null;
    if (!_isCurrentCommand(
          walletId: walletId,
          routeExecutionId: routeExecutionId,
          scopeGeneration: scopeGeneration,
          commandGeneration: commandGeneration,
          emit: emit,
        ) ||
        _sessionGeneration != reconciliationGeneration) {
      return;
    }
    emit(
      state.copyWith(
        status: RouteExecutionLoadStatus.reattaching,
        controlInFlight: true,
        failure: failure,
        announcement: RouteLiveAnnouncement.reattaching,
      ),
    );
    try {
      final attached = await _repository.reattachExecution(
        walletId: walletId,
        routeExecutionId: routeExecutionId,
      );
      if (!_isCurrentCommand(
            walletId: walletId,
            routeExecutionId: routeExecutionId,
            scopeGeneration: scopeGeneration,
            commandGeneration: commandGeneration,
            emit: emit,
          ) ||
          _sessionGeneration != reconciliationGeneration) {
        return;
      }
      if (attached.routeExecutionId != routeExecutionId) {
        _emitUnknownFailure(RouteExecutionFailure.conflict, emit);
        return;
      }
      await _observeSession(
        attached,
        reconciliationGeneration,
        emit,
        resetReconciliationGuard: false,
      );
    } on Object {
      if (_isCurrentCommand(
            walletId: walletId,
            routeExecutionId: routeExecutionId,
            scopeGeneration: scopeGeneration,
            commandGeneration: commandGeneration,
            emit: emit,
          ) &&
          _sessionGeneration == reconciliationGeneration) {
        _emitUnknownFailure(failure, emit);
      }
    }
  }

  void _finishCommand(int commandGeneration) {
    if (_commandGeneration == commandGeneration) {
      _commandInFlight = false;
      _commandAwaitingProgressGeneration = null;
    }
  }

  bool _finishCommandAwaitingProgress() {
    final commandGeneration = _commandAwaitingProgressGeneration;
    if (commandGeneration == null || commandGeneration != _commandGeneration) {
      return false;
    }
    _finishCommand(commandGeneration);
    return true;
  }

  bool _isCurrentCommand({
    required String walletId,
    required String routeExecutionId,
    required int scopeGeneration,
    required int commandGeneration,
    required Emitter<RouteExecutionState> emit,
  }) =>
      !emit.isDone &&
      state.walletId == walletId &&
      state.session?.routeExecutionId == routeExecutionId &&
      _scopeGeneration == scopeGeneration &&
      _commandGeneration == commandGeneration &&
      _commandInFlight;

  void _emitControlDenied(Emitter<RouteExecutionState> emit) {
    emit(
      state.copyWith(
        failure: RouteExecutionFailure.controlNotAuthorized,
        announcement: RouteLiveAnnouncement.statusUnavailable,
      ),
    );
  }

  bool _isCurrent(
    String walletId,
    int scopeGeneration,
    int sessionGeneration,
    Emitter<RouteExecutionState> emit,
  ) =>
      !emit.isDone &&
      state.walletId == walletId &&
      _scopeGeneration == scopeGeneration &&
      _sessionGeneration == sessionGeneration;

  void _emitFailure(
    RouteExecutionFailure failure,
    Emitter<RouteExecutionState> emit,
  ) {
    emit(
      state.copyWith(
        status: RouteExecutionLoadStatus.failed,
        controlInFlight: _commandInFlight,
        failure: failure,
        announcement: RouteLiveAnnouncement.statusUnavailable,
      ),
    );
  }

  void _emitPreInitFailure(
    RouteExecutionFailure failure,
    Emitter<RouteExecutionState> emit,
  ) {
    emit(
      state.copyWith(
        status: RouteExecutionLoadStatus.reviewRequired,
        clearSession: true,
        clearProgress: true,
        controlInFlight: false,
        failure: failure,
        announcement: RouteLiveAnnouncement.statusUnavailable,
        reviewRefreshStatus: RouteReviewRefreshStatus.latestTermsUnavailable,
        clearFreshQuote: true,
      ),
    );
  }

  void _emitUnknownFailure(
    RouteExecutionFailure failure,
    Emitter<RouteExecutionState> emit,
  ) {
    emit(
      state.copyWith(
        status: RouteExecutionLoadStatus.unknown,
        controlInFlight: _commandInFlight,
        failure: failure,
        announcement: RouteLiveAnnouncement.statusUnavailable,
      ),
    );
  }

  @override
  Future<void> close() async {
    _sessionGeneration++;
    await _observation?.cancel();
    _observation = null;
    await super.close();
  }
}

bool _hasActiveExecution(RouteExecutionLoadStatus status) =>
    status == RouteExecutionLoadStatus.starting ||
    status == RouteExecutionLoadStatus.reattaching ||
    status == RouteExecutionLoadStatus.observing ||
    status == RouteExecutionLoadStatus.attentionRequired ||
    status == RouteExecutionLoadStatus.recovery;

bool _reattachWouldInterruptStart(RouteExecutionLoadStatus status) =>
    status == RouteExecutionLoadStatus.starting ||
    status == RouteExecutionLoadStatus.reattaching;

bool _requiresDurableInitReconciliation(RouteExecutionFailure failure) =>
    failure != RouteExecutionFailure.invalidReview &&
    failure != RouteExecutionFailure.reviewExpired &&
    failure != RouteExecutionFailure.capabilityUnavailable;

RouteExecutionFailure _observationFailure(Object error) =>
    error is RouteExecutionException
    ? error.failure
    : RouteExecutionFailure.unknown;

bool _canAdvanceProgress(
  RouteExecutionProgress previous,
  RouteExecutionProgress next,
) {
  if (_isTerminalOutcome(previous.outcome) ||
      next.updatedAt.isBefore(previous.updatedAt) ||
      next.stageCount != previous.stageCount ||
      next.stageIndex < previous.stageIndex ||
      previous.transactionHashes.any(
        (hash) => !next.transactionHashes.contains(hash),
      ) ||
      (previous.stages.isNotEmpty &&
          !_sameReviewSteps(previous.stages, next.stages)) ||
      previous.stageResults.any(
        (result) => !next.stageResults.any(
          (candidate) =>
              candidate.sequence == result.sequence &&
              candidate.stageId == result.stageId,
        ),
      )) {
    return false;
  }
  if (next.stageIndex != previous.stageIndex) return true;
  final previousRank = _linearPhaseRank(previous.phase);
  final nextRank = _linearPhaseRank(next.phase);
  return previousRank == null || nextRank == null || nextRank >= previousRank;
}

bool _sameReviewSteps(
  List<RouteReviewStep> left,
  List<RouteReviewStep> right,
) =>
    left.length == right.length &&
    left.indexed.every((entry) => entry.$2 == right[entry.$1]);

int? _linearPhaseRank(RouteExecutionPhase phase) => switch (phase) {
  RouteExecutionPhase.validating => 0,
  RouteExecutionPhase.awaitingApproval => 1,
  RouteExecutionPhase.approvalPending => 2,
  RouteExecutionPhase.awaitingSignature => 3,
  RouteExecutionPhase.signed => 4,
  RouteExecutionPhase.broadcasting => 5,
  RouteExecutionPhase.sourcePending => 6,
  RouteExecutionPhase.sourceConfirmed => 7,
  RouteExecutionPhase.bridgePending => 8,
  RouteExecutionPhase.destinationConfirmed => 9,
  RouteExecutionPhase.atomicFill => 10,
  RouteExecutionPhase.awaitingUserAction ||
  RouteExecutionPhase.stopAfterCurrent ||
  RouteExecutionPhase.partial ||
  RouteExecutionPhase.refundPending ||
  RouteExecutionPhase.refunded ||
  RouteExecutionPhase.manualIntervention ||
  RouteExecutionPhase.completed ||
  RouteExecutionPhase.cancelled ||
  RouteExecutionPhase.failed ||
  RouteExecutionPhase.unknown => null,
};

bool _isTerminalOutcome(RouteExecutionOutcome outcome) =>
    outcome == RouteExecutionOutcome.completed ||
    outcome == RouteExecutionOutcome.cancelled ||
    outcome == RouteExecutionOutcome.failed;

RouteExecutionLoadStatus _statusFor(RouteExecutionProgress progress) {
  if (!progress.isExecutable) return RouteExecutionLoadStatus.unknown;
  return switch (progress.outcome) {
    RouteExecutionOutcome.active => RouteExecutionLoadStatus.observing,
    RouteExecutionOutcome.attentionRequired =>
      RouteExecutionLoadStatus.attentionRequired,
    RouteExecutionOutcome.recovery => RouteExecutionLoadStatus.recovery,
    RouteExecutionOutcome.completed => RouteExecutionLoadStatus.completed,
    RouteExecutionOutcome.cancelled => RouteExecutionLoadStatus.cancelled,
    RouteExecutionOutcome.failed => RouteExecutionLoadStatus.failed,
    RouteExecutionOutcome.unknown => RouteExecutionLoadStatus.unknown,
  };
}
