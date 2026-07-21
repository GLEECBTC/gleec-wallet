import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_repository.dart';

sealed class UnifiedSwapEvent extends Equatable {
  const UnifiedSwapEvent();

  @override
  List<Object?> get props => const [];
}

final class UnifiedSwapIntentChanged extends UnifiedSwapEvent {
  const UnifiedSwapIntentChanged(this.intent);

  final UnifiedSwapIntent intent;

  @override
  List<Object?> get props => [intent];
}

/// Seeds wallet-owned defaults without starting network discovery.
///
/// Initial composition uses an exact activated pair, a wallet-owned recipient,
/// and a zero amount. The first valid customer amount change is what requests a
/// quote, so opening Swap never executes an implicit trade intent.
final class UnifiedSwapIntentSeeded extends UnifiedSwapEvent {
  const UnifiedSwapIntentSeeded(this.intent);

  final UnifiedSwapIntent intent;

  @override
  List<Object?> get props => [intent];
}

final class UnifiedSwapCandidateSelected extends UnifiedSwapEvent {
  const UnifiedSwapCandidateSelected(this.candidateId);

  final String candidateId;

  @override
  List<Object?> get props => [candidateId];
}

final class UnifiedSwapRevalidationRequested extends UnifiedSwapEvent {
  const UnifiedSwapRevalidationRequested();
}

/// Adopts the fresh evaluation produced by acceptance preflight after the
/// reviewed route changed structurally. The exact quote repository has already
/// retained its digest-bound bindings; this event only updates presentation.
final class UnifiedSwapFreshEvaluationAdopted extends UnifiedSwapEvent {
  const UnifiedSwapFreshEvaluationAdopted({
    required this.intent,
    required this.evaluation,
  });

  final UnifiedSwapIntent intent;
  final UnifiedSwapQuoteEvaluation evaluation;

  @override
  List<Object?> get props => [intent, evaluation];
}

final class UnifiedSwapWalletChanged extends UnifiedSwapEvent {
  const UnifiedSwapWalletChanged(this.walletId);

  final String? walletId;

  @override
  List<Object?> get props => [walletId];
}

final class _UnifiedSwapExpiryReached extends UnifiedSwapEvent {
  const _UnifiedSwapExpiryReached(this.evaluationId);

  final String evaluationId;

  @override
  List<Object?> get props => [evaluationId];
}

class UnifiedSwapState extends Equatable {
  const UnifiedSwapState({
    this.walletId,
    this.intent,
    this.status = UnifiedSwapQuoteStatus.idle,
    this.evaluation,
    this.selectedCandidateId,
    this.failure,
  });

  final String? walletId;
  final UnifiedSwapIntent? intent;
  final UnifiedSwapQuoteStatus status;
  final UnifiedSwapQuoteEvaluation? evaluation;
  final String? selectedCandidateId;
  final UnifiedSwapQuoteFailure? failure;

  List<UnifiedSwapQuoteCandidate> get candidates =>
      evaluation?.candidates ?? const [];

  UnifiedSwapQuoteCandidate? get selectedCandidate {
    final id = selectedCandidateId;
    if (id == null) return null;
    return _candidateById(candidates, id);
  }

  UnifiedSwapState copyWith({
    String? walletId,
    bool clearWalletId = false,
    UnifiedSwapIntent? intent,
    bool clearIntent = false,
    UnifiedSwapQuoteStatus? status,
    UnifiedSwapQuoteEvaluation? evaluation,
    bool clearEvaluation = false,
    String? selectedCandidateId,
    bool clearSelectedCandidate = false,
    UnifiedSwapQuoteFailure? failure,
    bool clearFailure = false,
  }) {
    return UnifiedSwapState(
      walletId: clearWalletId ? null : walletId ?? this.walletId,
      intent: clearIntent ? null : intent ?? this.intent,
      status: status ?? this.status,
      evaluation: clearEvaluation ? null : evaluation ?? this.evaluation,
      selectedCandidateId: clearSelectedCandidate
          ? null
          : selectedCandidateId ?? this.selectedCandidateId,
      failure: clearFailure ? null : failure ?? this.failure,
    );
  }

  @override
  List<Object?> get props => [
    walletId,
    intent,
    status,
    evaluation,
    selectedCandidateId,
    failure,
  ];
}

class UnifiedSwapBloc extends Bloc<UnifiedSwapEvent, UnifiedSwapState> {
  UnifiedSwapBloc({
    required UnifiedSwapQuoteRepository quoteRepository,
    DateTime Function()? now,
    UnifiedSwapState initialState = const UnifiedSwapState(),
  }) : _quoteRepository = quoteRepository,
       _now = now ?? (() => DateTime.now().toUtc()),
       super(initialState) {
    on<UnifiedSwapIntentSeeded>(_onIntentSeeded);
    on<UnifiedSwapIntentChanged>(_onIntentChanged, transformer: restartable());
    on<UnifiedSwapCandidateSelected>(_onCandidateSelected);
    on<UnifiedSwapRevalidationRequested>(
      _onRevalidationRequested,
      transformer: restartable(),
    );
    on<UnifiedSwapFreshEvaluationAdopted>(_onFreshEvaluationAdopted);
    on<UnifiedSwapWalletChanged>(_onWalletChanged);
    on<_UnifiedSwapExpiryReached>(_onExpiryReached);
  }

  final UnifiedSwapQuoteRepository _quoteRepository;
  final DateTime Function() _now;
  Timer? _expiryTimer;
  int _intentGeneration = 0;

  void _onIntentSeeded(
    UnifiedSwapIntentSeeded event,
    Emitter<UnifiedSwapState> emit,
  ) {
    if (state.walletId == null || state.intent != null) return;
    _intentGeneration++;
    _expiryTimer?.cancel();
    emit(
      state.copyWith(
        intent: event.intent,
        status: UnifiedSwapQuoteStatus.idle,
        clearEvaluation: true,
        clearSelectedCandidate: true,
        clearFailure: true,
      ),
    );
  }

  Future<void> _onIntentChanged(
    UnifiedSwapIntentChanged event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    final generation = ++_intentGeneration;
    _expiryTimer?.cancel();
    if (event.intent.sourceAmount == '0') {
      emit(
        state.copyWith(
          intent: event.intent,
          status: UnifiedSwapQuoteStatus.idle,
          clearEvaluation: true,
          clearSelectedCandidate: true,
          clearFailure: true,
        ),
      );
      return;
    }
    final tokenFailure = event.intent.tokenFailure;
    if (!event.intent.sourceSelection.isExecutable) {
      emit(
        state.copyWith(
          intent: event.intent,
          status: UnifiedSwapQuoteStatus.unavailable,
          clearEvaluation: true,
          clearSelectedCandidate: true,
          failure: UnifiedSwapQuoteFailure.invalidIntent,
        ),
      );
      return;
    }
    if (tokenFailure != null) {
      emit(
        state.copyWith(
          intent: event.intent,
          status: UnifiedSwapQuoteStatus.unavailable,
          clearEvaluation: true,
          clearSelectedCandidate: true,
          failure: tokenFailure,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        intent: event.intent,
        status: UnifiedSwapQuoteStatus.loading,
        clearEvaluation: true,
        clearSelectedCandidate: true,
        clearFailure: true,
      ),
    );

    try {
      final evaluation = await _quoteRepository.evaluate(event.intent);
      if (emit.isDone ||
          generation != _intentGeneration ||
          state.intent?.revision != event.intent.revision) {
        return;
      }
      if (evaluation.intentRevision != event.intent.revision) {
        emit(
          state.copyWith(
            status: UnifiedSwapQuoteStatus.unavailable,
            clearEvaluation: true,
            failure: UnifiedSwapQuoteFailure.invalidIntent,
          ),
        );
        return;
      }

      final candidates = evaluation.candidates
          .where((candidate) => !candidate.isExpiredAt(_now()))
          .toList(growable: false);
      final current = UnifiedSwapQuoteEvaluation(
        evaluationId: evaluation.evaluationId,
        intentRevision: evaluation.intentRevision,
        candidates: candidates,
      );
      if (candidates.isEmpty) {
        emit(
          state.copyWith(
            status: UnifiedSwapQuoteStatus.expired,
            evaluation: current,
            failure: UnifiedSwapQuoteFailure.quoteExpired,
          ),
        );
        return;
      }
      final selectedCandidateId = _defaultCandidateId(candidates);
      emit(
        state.copyWith(
          status: UnifiedSwapQuoteStatus.ready,
          evaluation: current,
          selectedCandidateId: selectedCandidateId,
          clearSelectedCandidate: selectedCandidateId == null,
          clearFailure: true,
        ),
      );
      _scheduleExpiry(current);
    } on UnifiedSwapQuoteException catch (error) {
      if (!emit.isDone && generation == _intentGeneration) {
        emit(
          state.copyWith(
            status: UnifiedSwapQuoteStatus.unavailable,
            clearEvaluation: true,
            failure: error.failure,
          ),
        );
      }
    } on Object {
      if (!emit.isDone && generation == _intentGeneration) {
        emit(
          state.copyWith(
            status: UnifiedSwapQuoteStatus.unavailable,
            clearEvaluation: true,
            failure: UnifiedSwapQuoteFailure.unknown,
          ),
        );
      }
    }
  }

  void _onCandidateSelected(
    UnifiedSwapCandidateSelected event,
    Emitter<UnifiedSwapState> emit,
  ) {
    if (state.status != UnifiedSwapQuoteStatus.ready) return;
    final candidate = _candidateById(state.candidates, event.candidateId);
    if (candidate == null ||
        !candidate.isSafelyExecutable ||
        candidate.isExpiredAt(_now())) {
      return;
    }
    emit(state.copyWith(selectedCandidateId: candidate.candidateId));
  }

  void _onRevalidationRequested(
    UnifiedSwapRevalidationRequested event,
    Emitter<UnifiedSwapState> emit,
  ) {
    final intent = state.intent;
    if (intent != null) add(UnifiedSwapIntentChanged(intent));
  }

  void _onFreshEvaluationAdopted(
    UnifiedSwapFreshEvaluationAdopted event,
    Emitter<UnifiedSwapState> emit,
  ) {
    if (state.walletId == null ||
        state.intent != event.intent ||
        event.evaluation.intentRevision != event.intent.revision) {
      return;
    }
    _intentGeneration++;
    _expiryTimer?.cancel();
    final candidates = event.evaluation.candidates
        .where((candidate) => !candidate.isExpiredAt(_now()))
        .toList(growable: false);
    final evaluation = UnifiedSwapQuoteEvaluation(
      evaluationId: event.evaluation.evaluationId,
      intentRevision: event.evaluation.intentRevision,
      candidates: candidates,
    );
    if (candidates.isEmpty) {
      emit(
        state.copyWith(
          status: UnifiedSwapQuoteStatus.expired,
          evaluation: evaluation,
          clearSelectedCandidate: true,
          failure: UnifiedSwapQuoteFailure.quoteExpired,
        ),
      );
      return;
    }
    final selectedCandidateId = _defaultCandidateId(candidates);
    emit(
      state.copyWith(
        status: UnifiedSwapQuoteStatus.ready,
        evaluation: evaluation,
        selectedCandidateId: selectedCandidateId,
        clearSelectedCandidate: selectedCandidateId == null,
        clearFailure: true,
      ),
    );
    _scheduleExpiry(evaluation);
  }

  void _onWalletChanged(
    UnifiedSwapWalletChanged event,
    Emitter<UnifiedSwapState> emit,
  ) {
    _intentGeneration++;
    _expiryTimer?.cancel();
    emit(UnifiedSwapState(walletId: event.walletId));
  }

  void _onExpiryReached(
    _UnifiedSwapExpiryReached event,
    Emitter<UnifiedSwapState> emit,
  ) {
    final evaluation = state.evaluation;
    if (evaluation?.evaluationId != event.evaluationId) return;
    final candidates = evaluation!.candidates
        .where((candidate) => !candidate.isExpiredAt(_now()))
        .toList(growable: false);
    if (candidates.isNotEmpty) {
      final current = UnifiedSwapQuoteEvaluation(
        evaluationId: evaluation.evaluationId,
        intentRevision: evaluation.intentRevision,
        candidates: candidates,
      );
      final selectionIsCurrent = candidates.any(
        (candidate) => candidate.candidateId == state.selectedCandidateId,
      );
      final selectedCandidateId = selectionIsCurrent
          ? state.selectedCandidateId
          : _defaultCandidateId(candidates);
      emit(
        state.copyWith(
          status: UnifiedSwapQuoteStatus.ready,
          evaluation: current,
          selectedCandidateId: selectedCandidateId,
          clearSelectedCandidate: selectedCandidateId == null,
          clearFailure: true,
        ),
      );
      _scheduleExpiry(current);
      return;
    }
    emit(
      state.copyWith(
        status: UnifiedSwapQuoteStatus.expired,
        clearSelectedCandidate: true,
        failure: UnifiedSwapQuoteFailure.quoteExpired,
      ),
    );
  }

  void _scheduleExpiry(UnifiedSwapQuoteEvaluation evaluation) {
    _expiryTimer?.cancel();
    final expiry = evaluation.earliestExpiry;
    if (expiry == null) return;
    final delay = expiry.difference(_now());
    if (delay <= Duration.zero) {
      add(_UnifiedSwapExpiryReached(evaluation.evaluationId));
      return;
    }
    _expiryTimer = Timer(
      delay,
      () => add(_UnifiedSwapExpiryReached(evaluation.evaluationId)),
    );
  }

  @override
  Future<void> close() {
    _expiryTimer?.cancel();
    return super.close();
  }
}

String? _defaultCandidateId(List<UnifiedSwapQuoteCandidate> candidates) {
  final safe = candidates.where(_isSafeCandidate).toList(growable: false);
  final ranked = safe.where((candidate) => candidate.rankable).toList()
    ..sort((left, right) => left.rank!.compareTo(right.rank!));
  if (ranked.isNotEmpty) return ranked.first.candidateId;

  // When KDF cannot compare multiple routes honestly, require an explicit
  // customer choice. A sole safe route needs no artificial comparison step.
  return safe.length == 1 ? safe.single.candidateId : null;
}

bool _isSafeCandidate(UnifiedSwapQuoteCandidate candidate) =>
    candidate.isSafelyExecutable;

UnifiedSwapQuoteCandidate? _candidateById(
  Iterable<UnifiedSwapQuoteCandidate> candidates,
  String candidateId,
) {
  for (final candidate in candidates) {
    if (candidate.candidateId == candidateId) return candidate;
  }
  return null;
}
