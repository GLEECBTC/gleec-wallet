import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_repository.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_model_limits.dart';

sealed class RouteActivityEvent extends Equatable {
  const RouteActivityEvent();

  @override
  List<Object?> get props => const [];
}

final class RouteActivityWalletChanged extends RouteActivityEvent {
  const RouteActivityWalletChanged(this.walletId);

  final String? walletId;

  @override
  List<Object?> get props => [walletId];
}

final class RouteActivityRefreshRequested extends RouteActivityEvent {
  const RouteActivityRefreshRequested();
}

final class RouteActivityLoadMoreRequested extends RouteActivityEvent {
  const RouteActivityLoadMoreRequested();
}

final class RouteActivityExecutionRequested extends RouteActivityEvent {
  const RouteActivityExecutionRequested(this.routeExecutionId);

  final String routeExecutionId;

  @override
  List<Object?> get props => [routeExecutionId];
}

final class RouteActivityAppResumed extends RouteActivityEvent {
  const RouteActivityAppResumed();
}

enum RouteActivityLoadStatus {
  idle,
  loading,
  refreshing,
  ready,
  loadingMore,
  unavailable,
}

class RouteActivityState extends Equatable {
  RouteActivityState({
    this.walletId,
    this.status = RouteActivityLoadStatus.idle,
    List<RouteActivitySummary> executions = const [],
    this.nextCursor,
    this.requestedRouteExecutionId,
    this.selectedExecution,
    this.isDetailLoading = false,
    this.failure,
  }) : executions = List.unmodifiable(executions) {
    UnifiedSwapModelLimits.requireOptionalString(walletId, 'walletId');
    UnifiedSwapModelLimits.requireOptionalString(nextCursor, 'nextCursor');
    UnifiedSwapModelLimits.requireOptionalString(
      requestedRouteExecutionId,
      'requestedRouteExecutionId',
    );
    UnifiedSwapModelLimits.requireListLength(
      executions.length,
      'executions',
      maximumLength: UnifiedSwapModelLimits.activityItems,
    );
    if (executions.map((item) => item.routeExecutionId).toSet().length !=
        executions.length) {
      throw ArgumentError('Activity state must not contain duplicate routes');
    }
    if (requestedRouteExecutionId != null &&
        selectedExecution != null &&
        selectedExecution!.summary.routeExecutionId !=
            requestedRouteExecutionId) {
      throw ArgumentError(
        'The selected execution must match the requested route',
      );
    }
  }

  final String? walletId;
  final RouteActivityLoadStatus status;
  final List<RouteActivitySummary> executions;
  final String? nextCursor;
  final String? requestedRouteExecutionId;
  final RouteExecutionDetail? selectedExecution;
  final bool isDetailLoading;
  final RouteActivityFailure? failure;

  bool get hasMore => nextCursor != null;

  Map<RouteActivityGroup, List<RouteActivitySummary>> get grouped {
    final result = <RouteActivityGroup, List<RouteActivitySummary>>{
      for (final group in RouteActivityGroup.values)
        group: <RouteActivitySummary>[],
    };
    for (final execution in executions) {
      result[execution.group]!.add(execution);
    }
    return {
      for (final entry in result.entries)
        entry.key: List.unmodifiable(entry.value),
    };
  }

  RouteActivityState copyWith({
    String? walletId,
    bool clearWalletId = false,
    RouteActivityLoadStatus? status,
    List<RouteActivitySummary>? executions,
    String? nextCursor,
    bool clearNextCursor = false,
    String? requestedRouteExecutionId,
    bool clearRequestedRouteExecutionId = false,
    RouteExecutionDetail? selectedExecution,
    bool clearSelectedExecution = false,
    bool? isDetailLoading,
    RouteActivityFailure? failure,
    bool clearFailure = false,
  }) {
    return RouteActivityState(
      walletId: clearWalletId ? null : walletId ?? this.walletId,
      status: status ?? this.status,
      executions: executions ?? this.executions,
      nextCursor: clearNextCursor ? null : nextCursor ?? this.nextCursor,
      requestedRouteExecutionId: clearRequestedRouteExecutionId
          ? null
          : requestedRouteExecutionId ?? this.requestedRouteExecutionId,
      selectedExecution: clearSelectedExecution
          ? null
          : selectedExecution ?? this.selectedExecution,
      isDetailLoading: isDetailLoading ?? this.isDetailLoading,
      failure: clearFailure ? null : failure ?? this.failure,
    );
  }

  @override
  List<Object?> get props => [
    walletId,
    status,
    executions,
    nextCursor,
    requestedRouteExecutionId,
    selectedExecution,
    isDetailLoading,
    failure,
  ];
}

class RouteActivityBloc extends Bloc<RouteActivityEvent, RouteActivityState> {
  RouteActivityBloc({
    required RouteActivityRepository repository,
    RouteActivityState? initialState,
  }) : _repository = repository,
       super(initialState ?? RouteActivityState()) {
    on<RouteActivityWalletChanged>(
      _onWalletChanged,
      transformer: restartable(),
    );
    on<RouteActivityRefreshRequested>(
      _onRefreshRequested,
      transformer: restartable(),
    );
    on<RouteActivityLoadMoreRequested>(
      _onLoadMoreRequested,
      transformer: droppable(),
    );
    on<RouteActivityExecutionRequested>(
      _onExecutionRequested,
      transformer: restartable(),
    );
    on<RouteActivityAppResumed>(_onAppResumed, transformer: restartable());
  }

  final RouteActivityRepository _repository;
  int _scopeGeneration = 0;
  int _listGeneration = 0;
  int _detailGeneration = 0;

  Future<void> _onWalletChanged(
    RouteActivityWalletChanged event,
    Emitter<RouteActivityState> emit,
  ) async {
    final scopeGeneration = ++_scopeGeneration;
    final listGeneration = ++_listGeneration;
    _detailGeneration++;
    final walletId = event.walletId;
    emit(RouteActivityState(walletId: walletId));
    if (walletId == null) return;

    emit(
      RouteActivityState(
        walletId: walletId,
        status: RouteActivityLoadStatus.loading,
      ),
    );
    await _replaceFirstPage(
      walletId: walletId,
      scopeGeneration: scopeGeneration,
      listGeneration: listGeneration,
      emit: emit,
    );
  }

  Future<void> _onRefreshRequested(
    RouteActivityRefreshRequested event,
    Emitter<RouteActivityState> emit,
  ) async {
    await _reconcile(emit);
  }

  Future<void> _onAppResumed(
    RouteActivityAppResumed event,
    Emitter<RouteActivityState> emit,
  ) async {
    await _reconcile(emit);
  }

  Future<void> _reconcile(Emitter<RouteActivityState> emit) async {
    final walletId = state.walletId;
    if (walletId == null) return;
    final scopeGeneration = _scopeGeneration;
    final listGeneration = ++_listGeneration;
    final detailGeneration = ++_detailGeneration;
    final selectedRouteId =
        state.requestedRouteExecutionId ??
        state.selectedExecution?.summary.routeExecutionId;
    emit(
      state.copyWith(
        status: RouteActivityLoadStatus.refreshing,
        isDetailLoading: selectedRouteId != null,
        clearFailure: true,
      ),
    );

    try {
      final page = await _repository.listExecutions(walletId: walletId);
      if (!_isCurrentList(walletId, scopeGeneration, listGeneration, emit)) {
        return;
      }
      final detailWasSuperseded = _detailGeneration != detailGeneration;
      emit(
        state.copyWith(
          status: RouteActivityLoadStatus.ready,
          executions: _sortExecutions(page.executions),
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
          isDetailLoading: detailWasSuperseded
              ? state.isDetailLoading
              : selectedRouteId != null,
          clearFailure: true,
        ),
      );

      if (selectedRouteId == null || detailWasSuperseded) return;
      try {
        final detail = await _repository.getExecution(
          walletId: walletId,
          routeExecutionId: selectedRouteId,
        );
        if (!_isCurrentDetail(
          walletId,
          scopeGeneration,
          detailGeneration,
          emit,
        )) {
          return;
        }
        if (detail.summary.routeExecutionId != selectedRouteId) {
          _emitRefreshedDetailFailure(
            walletId,
            scopeGeneration,
            detailGeneration,
            RouteActivityFailure.serviceUnavailable,
            emit,
          );
          return;
        }
        emit(
          state.copyWith(
            selectedExecution: detail,
            isDetailLoading: false,
            clearFailure: true,
          ),
        );
      } on RouteActivityException catch (error) {
        _emitRefreshedDetailFailure(
          walletId,
          scopeGeneration,
          detailGeneration,
          error.failure,
          emit,
        );
      } on Object {
        _emitRefreshedDetailFailure(
          walletId,
          scopeGeneration,
          detailGeneration,
          RouteActivityFailure.unknown,
          emit,
        );
      }
    } on RouteActivityException catch (error) {
      _emitReconciliationFailure(
        walletId,
        scopeGeneration,
        listGeneration,
        error.failure,
        emit,
        detailGeneration: detailGeneration,
      );
    } on Object {
      _emitReconciliationFailure(
        walletId,
        scopeGeneration,
        listGeneration,
        RouteActivityFailure.unknown,
        emit,
        detailGeneration: detailGeneration,
      );
    }
  }

  Future<void> _onLoadMoreRequested(
    RouteActivityLoadMoreRequested event,
    Emitter<RouteActivityState> emit,
  ) async {
    final walletId = state.walletId;
    final cursor = state.nextCursor;
    if (walletId == null ||
        cursor == null ||
        state.status != RouteActivityLoadStatus.ready) {
      return;
    }
    final scopeGeneration = _scopeGeneration;
    final listGeneration = _listGeneration;
    emit(
      state.copyWith(
        status: RouteActivityLoadStatus.loadingMore,
        clearFailure: true,
      ),
    );

    try {
      final page = await _repository.listExecutions(
        walletId: walletId,
        cursor: cursor,
      );
      if (!_isCurrentList(walletId, scopeGeneration, listGeneration, emit)) {
        return;
      }
      if (state.status != RouteActivityLoadStatus.loadingMore ||
          state.nextCursor != cursor) {
        return;
      }
      emit(
        state.copyWith(
          status: RouteActivityLoadStatus.ready,
          executions: _mergeExecutions(state.executions, page.executions),
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
          clearFailure: true,
        ),
      );
    } on RouteActivityException catch (error) {
      _emitPageFailure(
        walletId,
        scopeGeneration,
        listGeneration,
        error.failure,
        emit,
      );
    } on Object {
      _emitPageFailure(
        walletId,
        scopeGeneration,
        listGeneration,
        RouteActivityFailure.unknown,
        emit,
      );
    }
  }

  Future<void> _onExecutionRequested(
    RouteActivityExecutionRequested event,
    Emitter<RouteActivityState> emit,
  ) async {
    final walletId = state.walletId;
    if (walletId == null ||
        !UnifiedSwapModelLimits.isCanonicalString(event.routeExecutionId)) {
      return;
    }
    final scopeGeneration = _scopeGeneration;
    final detailGeneration = ++_detailGeneration;
    emit(
      state.copyWith(
        requestedRouteExecutionId: event.routeExecutionId,
        isDetailLoading: true,
        clearSelectedExecution: true,
        clearFailure: true,
      ),
    );

    try {
      final detail = await _repository.getExecution(
        walletId: walletId,
        routeExecutionId: event.routeExecutionId,
      );
      if (!_isCurrentDetail(
        walletId,
        scopeGeneration,
        detailGeneration,
        emit,
      )) {
        return;
      }
      if (detail.summary.routeExecutionId != event.routeExecutionId) {
        _emitDetailFailure(
          walletId,
          scopeGeneration,
          detailGeneration,
          RouteActivityFailure.serviceUnavailable,
          emit,
        );
        return;
      }
      emit(
        state.copyWith(
          selectedExecution: detail,
          isDetailLoading: false,
          clearFailure: true,
        ),
      );
    } on RouteActivityException catch (error) {
      _emitDetailFailure(
        walletId,
        scopeGeneration,
        detailGeneration,
        error.failure,
        emit,
      );
    } on Object {
      _emitDetailFailure(
        walletId,
        scopeGeneration,
        detailGeneration,
        RouteActivityFailure.unknown,
        emit,
      );
    }
  }

  Future<void> _replaceFirstPage({
    required String walletId,
    required int scopeGeneration,
    required int listGeneration,
    required Emitter<RouteActivityState> emit,
  }) async {
    try {
      final page = await _repository.listExecutions(walletId: walletId);
      if (!_isCurrentList(walletId, scopeGeneration, listGeneration, emit)) {
        return;
      }
      emit(
        state.copyWith(
          status: RouteActivityLoadStatus.ready,
          executions: _sortExecutions(page.executions),
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
          clearFailure: true,
        ),
      );
    } on RouteActivityException catch (error) {
      _emitReconciliationFailure(
        walletId,
        scopeGeneration,
        listGeneration,
        error.failure,
        emit,
      );
    } on Object {
      _emitReconciliationFailure(
        walletId,
        scopeGeneration,
        listGeneration,
        RouteActivityFailure.unknown,
        emit,
      );
    }
  }

  bool _isCurrentList(
    String walletId,
    int scopeGeneration,
    int listGeneration,
    Emitter<RouteActivityState> emit,
  ) =>
      !emit.isDone &&
      state.walletId == walletId &&
      _scopeGeneration == scopeGeneration &&
      _listGeneration == listGeneration;

  bool _isCurrentDetail(
    String walletId,
    int scopeGeneration,
    int detailGeneration,
    Emitter<RouteActivityState> emit,
  ) =>
      !emit.isDone &&
      state.walletId == walletId &&
      _scopeGeneration == scopeGeneration &&
      _detailGeneration == detailGeneration;

  void _emitReconciliationFailure(
    String walletId,
    int scopeGeneration,
    int listGeneration,
    RouteActivityFailure failure,
    Emitter<RouteActivityState> emit, {
    int? detailGeneration,
  }) {
    if (!_isCurrentList(walletId, scopeGeneration, listGeneration, emit)) {
      return;
    }
    emit(
      state.copyWith(
        status: state.executions.isEmpty
            ? RouteActivityLoadStatus.unavailable
            : RouteActivityLoadStatus.ready,
        isDetailLoading:
            detailGeneration != null && _detailGeneration != detailGeneration
            ? state.isDetailLoading
            : false,
        failure: failure,
      ),
    );
  }

  void _emitPageFailure(
    String walletId,
    int scopeGeneration,
    int listGeneration,
    RouteActivityFailure failure,
    Emitter<RouteActivityState> emit,
  ) {
    if (!_isCurrentList(walletId, scopeGeneration, listGeneration, emit) ||
        state.status != RouteActivityLoadStatus.loadingMore) {
      return;
    }
    emit(
      state.copyWith(status: RouteActivityLoadStatus.ready, failure: failure),
    );
  }

  void _emitDetailFailure(
    String walletId,
    int scopeGeneration,
    int detailGeneration,
    RouteActivityFailure failure,
    Emitter<RouteActivityState> emit,
  ) {
    if (!_isCurrentDetail(walletId, scopeGeneration, detailGeneration, emit)) {
      return;
    }
    emit(
      state.copyWith(
        isDetailLoading: false,
        clearSelectedExecution: true,
        failure: failure,
      ),
    );
  }

  void _emitRefreshedDetailFailure(
    String walletId,
    int scopeGeneration,
    int detailGeneration,
    RouteActivityFailure failure,
    Emitter<RouteActivityState> emit,
  ) {
    if (!_isCurrentDetail(walletId, scopeGeneration, detailGeneration, emit)) {
      return;
    }
    emit(state.copyWith(isDetailLoading: false, failure: failure));
  }
}

List<RouteActivitySummary> _mergeExecutions(
  Iterable<RouteActivitySummary> current,
  Iterable<RouteActivitySummary> incoming,
) {
  final byId = <String, RouteActivitySummary>{
    for (final execution in current) execution.routeExecutionId: execution,
  };
  for (final execution in incoming) {
    byId[execution.routeExecutionId] = execution;
  }
  return _sortExecutions(byId.values);
}

List<RouteActivitySummary> _sortExecutions(
  Iterable<RouteActivitySummary> executions,
) {
  final sorted = [...executions];
  sorted.sort((left, right) {
    final updated = right.updatedAt.compareTo(left.updatedAt);
    if (updated != 0) return updated;
    return right.routeExecutionId.compareTo(left.routeExecutionId);
  });
  return List.unmodifiable(sorted);
}
