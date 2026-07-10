import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';

sealed class GnosisCardEvent extends Equatable {
  const GnosisCardEvent();
  @override
  List<Object?> get props => const [];
}

final class GnosisCardStarted extends GnosisCardEvent {
  const GnosisCardStarted();
}

final class GnosisCardAdvanceRequested extends GnosisCardEvent {
  const GnosisCardAdvanceRequested();
}

final class GnosisPhysicalCardRequested extends GnosisCardEvent {
  const GnosisPhysicalCardRequested();
}

final class GnosisCardFreezeChanged extends GnosisCardEvent {
  const GnosisCardFreezeChanged(this.cardId, {required this.frozen});
  final String cardId;
  final bool frozen;

  @override
  List<Object?> get props => [cardId, frozen];
}

final class GnosisCardStatusChanged extends GnosisCardEvent {
  const GnosisCardStatusChanged(this.cardId, this.status);
  final String cardId;
  final GnosisCardStatus status;

  @override
  List<Object?> get props => [cardId, status];
}

final class GnosisCardControlsChanged extends GnosisCardEvent {
  const GnosisCardControlsChanged(this.controls);
  final GnosisCardControls controls;

  @override
  List<Object?> get props => [controls];
}

final class GnosisWithdrawalReviewRequested extends GnosisCardEvent {
  const GnosisWithdrawalReviewRequested(this.request);
  final WithdrawalRequest request;

  @override
  List<Object?> get props => [request];
}

final class GnosisDailyLimitReviewRequested extends GnosisCardEvent {
  const GnosisDailyLimitReviewRequested(this.request);
  final DailyLimitRequest request;

  @override
  List<Object?> get props => [request];
}

final class GnosisPreparedIntentConfirmed extends GnosisCardEvent {
  const GnosisPreparedIntentConfirmed();
}

final class GnosisPreparedIntentCancelled extends GnosisCardEvent {
  const GnosisPreparedIntentCancelled();
}

final class GnosisDelayedOperationsRefreshRequested extends GnosisCardEvent {
  const GnosisDelayedOperationsRefreshRequested();
}

enum GnosisCardLoadStatus { initial, loading, ready, failure, disabled }

class GnosisCardState extends Equatable {
  const GnosisCardState({required this.status, this.snapshot, this.message});

  const GnosisCardState.initial()
    : status = GnosisCardLoadStatus.initial,
      snapshot = null,
      message = null;

  final GnosisCardLoadStatus status;
  final GnosisCardSnapshot? snapshot;
  final String? message;

  GnosisCardState copyWith({
    GnosisCardLoadStatus? status,
    GnosisCardSnapshot? snapshot,
    String? message,
    bool clearMessage = false,
  }) => GnosisCardState(
    status: status ?? this.status,
    snapshot: snapshot ?? this.snapshot,
    message: clearMessage ? null : message ?? this.message,
  );

  @override
  List<Object?> get props => [status, snapshot, message];
}

class GnosisCardBloc extends Bloc<GnosisCardEvent, GnosisCardState> {
  GnosisCardBloc({
    required this.config,
    required this.coordinator,
    GnosisCardState initialState = const GnosisCardState.initial(),
  }) : super(initialState) {
    on<GnosisCardStarted>(_onStarted);
    on<GnosisCardAdvanceRequested>(
      (event, emit) => _run(emit, _coordinator.advance),
    );
    on<GnosisPhysicalCardRequested>(
      (event, emit) => _run(emit, _coordinator.orderPhysicalCard),
    );
    on<GnosisCardFreezeChanged>(
      (event, emit) =>
          _run(emit, () => _coordinator.setFrozen(event.cardId, event.frozen)),
    );
    on<GnosisCardStatusChanged>(
      (event, emit) => _run(
        emit,
        () => _coordinator.setCardStatus(event.cardId, event.status),
      ),
    );
    on<GnosisCardControlsChanged>(
      (event, emit) =>
          _run(emit, () => _coordinator.updateControls(event.controls)),
    );
    on<GnosisWithdrawalReviewRequested>(
      (event, emit) =>
          _run(emit, () => _coordinator.prepareWithdrawal(event.request)),
    );
    on<GnosisDailyLimitReviewRequested>(
      (event, emit) =>
          _run(emit, () => _coordinator.prepareDailyLimit(event.request)),
    );
    on<GnosisPreparedIntentConfirmed>(
      (event, emit) => _run(emit, _coordinator.confirmPreparedIntent),
    );
    on<GnosisDelayedOperationsRefreshRequested>(
      (event, emit) => _run(emit, _coordinator.pollDelayedOperations),
    );
    on<GnosisPreparedIntentCancelled>((event, emit) {
      emit(
        GnosisCardState(
          status: GnosisCardLoadStatus.ready,
          snapshot: _coordinator.cancelPreparedIntent(),
        ),
      );
    });
  }

  final GnosisCardConfig config;
  final GnosisCardCoordinator? coordinator;
  GnosisCardCoordinator get _coordinator {
    final value = coordinator;
    if (value == null) {
      throw StateError('Gnosis card dependencies are disabled.');
    }
    return value;
  }

  Future<void> _onStarted(
    GnosisCardStarted event,
    Emitter<GnosisCardState> emit,
  ) async {
    if (config.mode == GnosisCardMode.disabled) {
      emit(
        GnosisCardState(
          status: GnosisCardLoadStatus.disabled,
          message: config.failureReason,
        ),
      );
      return;
    }
    await _run(emit, _coordinator.initialize);
  }

  Future<void> _run(
    Emitter<GnosisCardState> emit,
    Future<GnosisCardSnapshot> Function() action,
  ) async {
    emit(
      state.copyWith(status: GnosisCardLoadStatus.loading, clearMessage: true),
    );
    try {
      final snapshot = await action();
      emit(
        GnosisCardState(status: GnosisCardLoadStatus.ready, snapshot: snapshot),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: GnosisCardLoadStatus.failure,
          message: error.toString(),
        ),
      );
    }
  }
}
