import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_repository.dart';

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

final class RouteExecutionCancelRequested extends RouteExecutionEvent {
  const RouteExecutionCancelRequested();
}

final class RouteExecutionStopAfterCurrentRequested
    extends RouteExecutionEvent {
  const RouteExecutionStopAfterCurrentRequested();
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

class RouteExecutionState extends Equatable {
  const RouteExecutionState({
    this.walletId,
    this.status = RouteExecutionLoadStatus.idle,
    this.review,
    this.session,
    this.progress,
    this.controlInFlight = false,
    this.failure,
    this.announcement = RouteLiveAnnouncement.none,
  });

  final String? walletId;
  final RouteExecutionLoadStatus status;
  final RouteExecutionReview? review;
  final RouteExecutionSession? session;
  final RouteExecutionProgress? progress;
  final bool controlInFlight;
  final RouteExecutionFailure? failure;
  final RouteLiveAnnouncement announcement;

  String? get routeExecutionId =>
      session?.routeExecutionId ?? review?.routeExecutionId;

  RouteExecutionState copyWith({
    String? walletId,
    bool clearWalletId = false,
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
  }) {
    return RouteExecutionState(
      walletId: clearWalletId ? null : walletId ?? this.walletId,
      status: status ?? this.status,
      review: clearReview ? null : review ?? this.review,
      session: clearSession ? null : session ?? this.session,
      progress: clearProgress ? null : progress ?? this.progress,
      controlInFlight: controlInFlight ?? this.controlInFlight,
      failure: clearFailure ? null : failure ?? this.failure,
      announcement: announcement ?? this.announcement,
    );
  }

  @override
  List<Object?> get props => [
    walletId,
    status,
    review,
    session,
    progress,
    controlInFlight,
    failure,
    announcement,
  ];
}

class RouteExecutionBloc
    extends Bloc<RouteExecutionEvent, RouteExecutionState> {
  RouteExecutionBloc({
    required RouteExecutionRepository repository,
    DateTime Function()? now,
    RouteExecutionState initialState = const RouteExecutionState(),
  }) : _repository = repository,
       _now = now ?? (() => DateTime.now().toUtc()),
       super(initialState) {
    on<RouteExecutionWalletChanged>(_onWalletChanged);
    on<RouteExecutionReviewPresented>(_onReviewPresented);
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
  }

  final RouteExecutionRepository _repository;
  final DateTime Function() _now;
  StreamSubscription<RouteExecutionProgress>? _observation;
  int _scopeGeneration = 0;
  int _sessionGeneration = 0;
  bool _observationReconciliationAttempted = false;

  Future<void> _onWalletChanged(
    RouteExecutionWalletChanged event,
    Emitter<RouteExecutionState> emit,
  ) async {
    _scopeGeneration++;
    _sessionGeneration++;
    _observationReconciliationAttempted = false;
    final observation = _observation;
    _observation = null;
    emit(RouteExecutionState(walletId: event.walletId));
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
    if (_hasActiveExecution(state.status)) return;
    emit(
      state.copyWith(
        status: RouteExecutionLoadStatus.reviewRequired,
        review: event.review,
        clearSession: true,
        clearProgress: true,
        controlInFlight: false,
        clearFailure: true,
        announcement: RouteLiveAnnouncement.none,
      ),
    );
  }

  Future<void> _onReviewAccepted(
    RouteExecutionReviewAccepted event,
    Emitter<RouteExecutionState> emit,
  ) async {
    final review = state.review;
    final walletId = state.walletId;
    if (walletId == null ||
        review == null ||
        state.status != RouteExecutionLoadStatus.reviewRequired ||
        event.reviewId != review.reviewId ||
        event.consentDigest != review.consentDigest ||
        !review.isExecutable) {
      emit(
        state.copyWith(
          failure: RouteExecutionFailure.invalidReview,
          announcement: RouteLiveAnnouncement.statusUnavailable,
        ),
      );
      return;
    }
    if (review.isExpiredAt(_now())) {
      emit(
        state.copyWith(
          failure: RouteExecutionFailure.reviewExpired,
          announcement: RouteLiveAnnouncement.statusUnavailable,
        ),
      );
      return;
    }

    final scopeGeneration = _scopeGeneration;
    final sessionGeneration = ++_sessionGeneration;
    emit(
      state.copyWith(
        status: RouteExecutionLoadStatus.starting,
        controlInFlight: false,
        clearFailure: true,
        announcement: RouteLiveAnnouncement.starting,
      ),
    );
    try {
      final session = await _repository.initReviewedExecution(
        walletId: walletId,
        routeExecutionId: review.routeExecutionId,
        reviewId: review.reviewId,
        consentDigest: review.consentDigest,
      );
      if (!_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        return;
      }
      if (session.routeExecutionId != review.routeExecutionId) {
        _emitFailure(RouteExecutionFailure.conflict, emit);
        return;
      }
      await _observeSession(session, sessionGeneration, emit);
    } on RouteExecutionException catch (error) {
      await _handleUncertainInitFailure(
        walletId: walletId,
        routeExecutionId: review.routeExecutionId,
        scopeGeneration: scopeGeneration,
        sessionGeneration: sessionGeneration,
        failure: error.failure,
        emit: emit,
      );
    } on Object {
      await _handleUncertainInitFailure(
        walletId: walletId,
        routeExecutionId: review.routeExecutionId,
        scopeGeneration: scopeGeneration,
        sessionGeneration: sessionGeneration,
        failure: RouteExecutionFailure.unknown,
        emit: emit,
      );
    }
  }

  Future<void> _handleUncertainInitFailure({
    required String walletId,
    required String routeExecutionId,
    required int scopeGeneration,
    required int sessionGeneration,
    required RouteExecutionFailure failure,
    required Emitter<RouteExecutionState> emit,
  }) async {
    if (!_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) return;
    if (!_requiresDurableInitReconciliation(failure)) {
      _emitFailure(failure, emit);
      return;
    }

    emit(
      state.copyWith(
        status: RouteExecutionLoadStatus.reattaching,
        controlInFlight: false,
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
    if (_reattachWouldInterruptStart(state.status)) return;
    await _reattach(event.routeExecutionId, emit);
  }

  Future<void> _onAppResumed(
    RouteExecutionAppResumed event,
    Emitter<RouteExecutionState> emit,
  ) async {
    if (_reattachWouldInterruptStart(state.status)) return;
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
        _reattachWouldInterruptStart(state.status)) {
      return;
    }
    final scopeGeneration = _scopeGeneration;
    final sessionGeneration = ++_sessionGeneration;
    emit(
      state.copyWith(
        status: RouteExecutionLoadStatus.reattaching,
        controlInFlight: false,
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
        _emitFailure(error.failure, emit);
      }
    } on Object {
      if (_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        _emitFailure(RouteExecutionFailure.unknown, emit);
      }
    }
  }

  Future<void> _observeSession(
    RouteExecutionSession session,
    int generation,
    Emitter<RouteExecutionState> emit, {
    bool resetReconciliationGuard = true,
  }) async {
    await _observation?.cancel();
    if (emit.isDone || generation != _sessionGeneration) return;
    if (resetReconciliationGuard) {
      _observationReconciliationAttempted = false;
    }
    emit(
      state.copyWith(
        status: RouteExecutionLoadStatus.observing,
        session: session,
        clearProgress: true,
        controlInFlight: false,
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
    emit(
      state.copyWith(
        status: _statusFor(event.progress),
        progress: event.progress,
        controlInFlight: false,
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
        controlInFlight: false,
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
    final progress = state.progress;
    if (!_canControl(progress) ||
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
    final progress = state.progress;
    if (!_canControl(progress) ||
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

  Future<void> _onDecisionSubmitted(
    RouteExecutionDecisionSubmitted event,
    Emitter<RouteExecutionState> emit,
  ) async {
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
    final sessionGeneration = _sessionGeneration;
    emit(state.copyWith(controlInFlight: true, clearFailure: true));
    try {
      final acknowledgement = await _repository.submitDecision(
        walletId: walletId,
        session: session,
        decision: event.decision,
      );
      if (_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        emit(
          state.copyWith(
            controlInFlight: false,
            failure: acknowledgement.wasDelivered
                ? null
                : RouteExecutionFailure.serviceUnavailable,
            clearFailure: acknowledgement.wasDelivered,
          ),
        );
      }
    } on RouteExecutionException catch (error) {
      if (_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        emit(state.copyWith(controlInFlight: false, failure: error.failure));
      }
    } on Object {
      if (_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        emit(
          state.copyWith(
            controlInFlight: false,
            failure: RouteExecutionFailure.unknown,
          ),
        );
      }
    }
  }

  bool _canControl(RouteExecutionProgress? progress) =>
      state.walletId != null &&
      state.session != null &&
      progress != null &&
      progress.isExecutable &&
      !state.controlInFlight;

  Future<void> _runControl(
    Emitter<RouteExecutionState> emit,
    Future<void> Function(String walletId, String routeExecutionId) control,
  ) async {
    final walletId = state.walletId!;
    final routeExecutionId = state.session!.routeExecutionId;
    final scopeGeneration = _scopeGeneration;
    final sessionGeneration = _sessionGeneration;
    emit(state.copyWith(controlInFlight: true, clearFailure: true));
    try {
      await control(walletId, routeExecutionId);
      if (_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        emit(state.copyWith(controlInFlight: false, clearFailure: true));
      }
    } on RouteExecutionException catch (error) {
      if (_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        emit(state.copyWith(controlInFlight: false, failure: error.failure));
      }
    } on Object {
      if (_isCurrent(walletId, scopeGeneration, sessionGeneration, emit)) {
        emit(
          state.copyWith(
            controlInFlight: false,
            failure: RouteExecutionFailure.unknown,
          ),
        );
      }
    }
  }

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
        controlInFlight: false,
        failure: failure,
        announcement: RouteLiveAnnouncement.statusUnavailable,
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
        controlInFlight: false,
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
