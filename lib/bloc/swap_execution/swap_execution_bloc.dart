import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// What a cancel request is doing.
enum SwapCancelStatus {
  /// No cancel requested.
  idle,

  /// Waiting for the engine's answer.
  cancelling,

  /// Refused: the transaction was already handed to the network.
  refusedAlreadySent,

  /// Refused: this swap cannot be stopped once it has begun.
  refusedNotSupported,

  /// The answer was lost. The swap may or may not have stopped; its status
  /// keeps reporting the truth.
  unconfirmed,
}

/// Events for [SwapExecutionBloc].
sealed class SwapExecutionEvent extends Equatable {
  const SwapExecutionEvent();

  @override
  List<Object?> get props => const [];
}

/// Follow the swap [id].
final class SwapExecutionWatched extends SwapExecutionEvent {
  const SwapExecutionWatched(this.id, {this.source, this.initial});

  /// The durable id.
  final String id;

  /// Which source runs it, when known.
  final SwapLiquiditySource? source;

  /// A snapshot already in hand — from Activity's history — shown until the
  /// live one arrives, so opening an old swap never starts on a spinner.
  final SwapExecutionSnapshot? initial;

  @override
  List<Object?> get props => [id, source, initial];
}

/// Stop the swap, confirmed by the user.
final class SwapExecutionCancelRequested extends SwapExecutionEvent {
  const SwapExecutionCancelRequested();
}

final class _SwapExecutionUpdated extends SwapExecutionEvent {
  const _SwapExecutionUpdated(this.snapshot);
  final SwapExecutionSnapshot snapshot;

  @override
  List<Object?> get props => [snapshot];
}

final class _SwapExecutionEnded extends SwapExecutionEvent {
  const _SwapExecutionEnded();
}

/// State for [SwapExecutionBloc].
class SwapExecutionState extends Equatable {
  const SwapExecutionState({
    this.snapshot,
    this.loading = true,
    this.notFound = false,
    this.cancelStatus = SwapCancelStatus.idle,
  });

  /// The latest snapshot.
  final SwapExecutionSnapshot? snapshot;

  /// Whether the first snapshot is still loading.
  final bool loading;

  /// Whether no source knows the swap.
  final bool notFound;

  /// What a cancel request is doing.
  final SwapCancelStatus cancelStatus;

  SwapExecutionState copyWith({
    SwapExecutionSnapshot? snapshot,
    bool? loading,
    bool? notFound,
    SwapCancelStatus? cancelStatus,
  }) => SwapExecutionState(
    snapshot: snapshot ?? this.snapshot,
    loading: loading ?? this.loading,
    notFound: notFound ?? this.notFound,
    cancelStatus: cancelStatus ?? this.cancelStatus,
  );

  @override
  List<Object?> get props => [snapshot, loading, notFound, cancelStatus];
}

/// Follows one swap for the progress and outcome screens.
///
/// The swap lives in the [SwapExecutionRegistry]; this only watches it, so
/// closing the screen stops the watching and never the swap.
class SwapExecutionBloc extends Bloc<SwapExecutionEvent, SwapExecutionState> {
  SwapExecutionBloc({required SwapExecutionRegistry registry})
    : _registry = registry,
      super(const SwapExecutionState()) {
    on<SwapExecutionWatched>(_onWatched);
    on<SwapExecutionCancelRequested>(_onCancelRequested);
    on<_SwapExecutionUpdated>(_onUpdated);
    on<_SwapExecutionEnded>(_onEnded);
  }

  final SwapExecutionRegistry _registry;
  StreamSubscription<SwapExecutionSnapshot>? _subscription;
  String? _id;

  Future<void> _onWatched(
    SwapExecutionWatched event,
    Emitter<SwapExecutionState> emit,
  ) async {
    if (_id == event.id) return;
    _id = event.id;
    await _subscription?.cancel();
    final known = _registry.snapshotOf(event.id) ?? event.initial;
    emit(SwapExecutionState(snapshot: known, loading: known == null));
    _subscription = _registry
        .watch(event.id, source: event.source)
        .listen(
          (snapshot) => add(_SwapExecutionUpdated(snapshot)),
          onDone: () => add(const _SwapExecutionEnded()),
          onError: (Object _) => add(const _SwapExecutionEnded()),
        );
    _registry.acknowledge(event.id);
  }

  void _onUpdated(
    _SwapExecutionUpdated event,
    Emitter<SwapExecutionState> emit,
  ) {
    emit(state.copyWith(snapshot: event.snapshot, loading: false));
    if (event.snapshot.isTerminal) _registry.acknowledge(event.snapshot.id);
  }

  void _onEnded(_SwapExecutionEnded event, Emitter<SwapExecutionState> emit) {
    if (state.snapshot == null) {
      emit(state.copyWith(loading: false, notFound: true));
    }
  }

  Future<void> _onCancelRequested(
    SwapExecutionCancelRequested event,
    Emitter<SwapExecutionState> emit,
  ) async {
    final id = _id;
    if (id == null || state.cancelStatus == SwapCancelStatus.cancelling) {
      return;
    }
    emit(state.copyWith(cancelStatus: SwapCancelStatus.cancelling));
    try {
      await _registry.cancel(id);
      emit(state.copyWith(cancelStatus: SwapCancelStatus.idle));
    } on SwapCancelRefusedException catch (error) {
      emit(
        state.copyWith(
          cancelStatus: switch (error.reason) {
            SwapCancelRefusal.alreadySent =>
              SwapCancelStatus.refusedAlreadySent,
            SwapCancelRefusal.alreadyFinished => SwapCancelStatus.idle,
            SwapCancelRefusal.notSupported =>
              SwapCancelStatus.refusedNotSupported,
          },
        ),
      );
    } on Object {
      emit(state.copyWith(cancelStatus: SwapCancelStatus.unconfirmed));
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
