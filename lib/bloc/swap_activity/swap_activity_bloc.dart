import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_history_repository.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// Events for [SwapActivityBloc].
sealed class SwapActivityEvent extends Equatable {
  const SwapActivityEvent();

  @override
  List<Object?> get props => const [];
}

/// Load Activity.
final class SwapActivityStarted extends SwapActivityEvent {
  const SwapActivityStarted({this.filter = SwapActivityFilter.active});

  /// The view to open on.
  final SwapActivityFilter filter;

  @override
  List<Object?> get props => [filter];
}

/// Switch between Active, Needs attention and Completed.
final class SwapActivityFilterChanged extends SwapActivityEvent {
  const SwapActivityFilterChanged(this.filter);

  /// The view.
  final SwapActivityFilter filter;

  @override
  List<Object?> get props => [filter];
}

/// Reload from the engine.
final class SwapActivityRefreshed extends SwapActivityEvent {
  const SwapActivityRefreshed();
}

/// Load older swaps.
final class SwapActivityMoreRequested extends SwapActivityEvent {
  const SwapActivityMoreRequested();
}

final class _SwapActivityLiveUpdated extends SwapActivityEvent {
  const _SwapActivityLiveUpdated(this.live);
  final List<SwapExecutionSnapshot> live;

  @override
  List<Object?> get props => [live];
}

/// What Activity is doing.
enum SwapActivityStatus {
  /// Loading.
  loading,

  /// Loaded; possibly partial — see [SwapActivityState.failedSources].
  ready,

  /// Nothing could be read at all.
  error,
}

/// State for [SwapActivityBloc].
class SwapActivityState extends Equatable {
  const SwapActivityState({
    this.filter = SwapActivityFilter.active,
    this.status = SwapActivityStatus.loading,
    this.history = const [],
    this.live = const [],
    this.failedSources = const {},
    this.hasMore = false,
    this.limit = SwapActivityBloc.pageSize,
    this.loadingMore = false,
  });

  /// The view.
  final SwapActivityFilter filter;

  /// What loading is doing.
  final SwapActivityStatus status;

  /// Swaps read from the engine for [filter].
  final List<SwapExecutionSnapshot> history;

  /// Swaps followed live this session, which may be newer than [history].
  final List<SwapExecutionSnapshot> live;

  /// Sources that could not be read.
  final Set<SwapLiquiditySource> failedSources;

  /// Whether older swaps may exist.
  final bool hasMore;

  /// How many swaps per source are loaded.
  final int limit;

  /// Whether older swaps are loading.
  final bool loadingMore;

  /// The swaps to show: history, with live snapshots replacing their stale
  /// counterparts and adding swaps history has not caught up with.
  List<SwapExecutionSnapshot> get entries {
    final byId = {for (final entry in history) entry.id: entry};
    for (final entry in live) {
      if (SwapHistoryRepository.matches(entry, filter)) {
        byId[entry.id] = entry;
      } else {
        byId.remove(entry.id);
      }
    }
    return byId.values.toList()..sort(SwapHistoryRepository.byNewest);
  }

  /// Whether the list may be missing swaps.
  bool get isPartial => failedSources.isNotEmpty;

  SwapActivityState copyWith({
    SwapActivityFilter? filter,
    SwapActivityStatus? status,
    List<SwapExecutionSnapshot>? history,
    List<SwapExecutionSnapshot>? live,
    Set<SwapLiquiditySource>? failedSources,
    bool? hasMore,
    int? limit,
    bool? loadingMore,
  }) => SwapActivityState(
    filter: filter ?? this.filter,
    status: status ?? this.status,
    history: history ?? this.history,
    live: live ?? this.live,
    failedSources: failedSources ?? this.failedSources,
    hasMore: hasMore ?? this.hasMore,
    limit: limit ?? this.limit,
    loadingMore: loadingMore ?? this.loadingMore,
  );

  @override
  List<Object?> get props => [
    filter,
    status,
    history,
    live,
    failedSources,
    hasMore,
    limit,
    loadingMore,
  ];
}

/// Drives Activity: swaps from both sources, filtered, with live updates for
/// the ones followed this session.
class SwapActivityBloc extends Bloc<SwapActivityEvent, SwapActivityState> {
  SwapActivityBloc({
    required SwapHistoryRepository history,
    required SwapExecutionRegistry registry,
  }) : _history = history,
       _registry = registry,
       super(const SwapActivityState()) {
    on<SwapActivityStarted>(_onStarted);
    on<SwapActivityFilterChanged>(_onFilterChanged);
    on<SwapActivityRefreshed>(_onRefreshed);
    on<SwapActivityMoreRequested>(_onMoreRequested);
    on<_SwapActivityLiveUpdated>(_onLiveUpdated);
  }

  /// Swaps loaded per source per page.
  static const pageSize = 25;

  final SwapHistoryRepository _history;
  final SwapExecutionRegistry _registry;
  StreamSubscription<List<SwapExecutionSnapshot>>? _live;
  int _loadVersion = 0;

  Future<void> _onStarted(
    SwapActivityStarted event,
    Emitter<SwapActivityState> emit,
  ) async {
    await _live?.cancel();
    _live = _registry.executions.listen(
      (live) => add(_SwapActivityLiveUpdated(live)),
    );
    emit(state.copyWith(filter: event.filter));
    await _load(emit, limit: pageSize);
  }

  Future<void> _onFilterChanged(
    SwapActivityFilterChanged event,
    Emitter<SwapActivityState> emit,
  ) async {
    if (event.filter == state.filter) return;
    emit(
      state.copyWith(
        filter: event.filter,
        status: SwapActivityStatus.loading,
        history: const [],
      ),
    );
    await _load(emit, limit: pageSize);
  }

  Future<void> _onRefreshed(
    SwapActivityRefreshed event,
    Emitter<SwapActivityState> emit,
  ) => _load(emit, limit: state.limit);

  Future<void> _onMoreRequested(
    SwapActivityMoreRequested event,
    Emitter<SwapActivityState> emit,
  ) async {
    if (!state.hasMore || state.loadingMore) return;
    emit(state.copyWith(loadingMore: true));
    await _load(emit, limit: state.limit + pageSize);
  }

  Future<void> _load(
    Emitter<SwapActivityState> emit, {
    required int limit,
  }) async {
    final version = ++_loadVersion;
    final filter = state.filter;
    try {
      final page = await _history.load(filter: filter, limit: limit);
      if (version != _loadVersion) return;
      final everythingFailed =
          page.failedSources.length == SwapLiquiditySource.values.length;
      emit(
        state.copyWith(
          status: everythingFailed && page.entries.isEmpty
              ? SwapActivityStatus.error
              : SwapActivityStatus.ready,
          history: page.entries,
          failedSources: page.failedSources,
          hasMore: page.hasMore,
          limit: limit,
          loadingMore: false,
        ),
      );
    } on Object {
      if (version != _loadVersion) return;
      emit(
        state.copyWith(status: SwapActivityStatus.error, loadingMore: false),
      );
    }
  }

  void _onLiveUpdated(
    _SwapActivityLiveUpdated event,
    Emitter<SwapActivityState> emit,
  ) {
    final previous = {for (final s in state.live) s.id: s};
    emit(state.copyWith(live: event.live));
    // A followed swap that just finished moves between views; reload so the
    // durable record (timestamps, gas spent) replaces the live snapshot.
    final finished = event.live.any(
      (s) => s.isTerminal && !(previous[s.id]?.isTerminal ?? true),
    );
    if (finished) add(const SwapActivityRefreshed());
  }

  @override
  Future<void> close() async {
    await _live?.cancel();
    return super.close();
  }
}
