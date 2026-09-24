import 'package:equatable/equatable.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/shared/swap/atomic_swap_execution.dart';
import 'package:web_dex/shared/swap/routed_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// The three views of Activity.
enum SwapActivityFilter {
  /// Still running.
  active,

  /// Finished, but not as asked, or with funds or a permission to check.
  attention,

  /// Finished with nothing left to do.
  completed,
}

/// A page of atomic swaps from the legacy recent-swaps list.
class AtomicSwapHistoryPage {
  const AtomicSwapHistoryPage({required this.swaps, required this.hasMore});

  /// The swaps, newest first.
  final List<Swap> swaps;

  /// Whether a later page exists.
  final bool hasMore;
}

/// Reads one page of atomic swap history.
typedef AtomicSwapHistoryReader =
    Future<AtomicSwapHistoryPage> Function({
      required int limit,
      required int page,
    });

/// One page of merged Activity.
class SwapActivityPage extends Equatable {
  const SwapActivityPage({
    required this.entries,
    required this.failedSources,
    required this.hasMore,
  });

  /// The swaps, newest first.
  final List<SwapExecutionSnapshot> entries;

  /// Sources that could not be read. Non-empty means the list is incomplete —
  /// "we could not check" is not the same statement as "you have none".
  final Set<SwapLiquiditySource> failedSources;

  /// Whether loading more may find older swaps.
  final bool hasMore;

  /// Whether anything is missing from this page.
  bool get isPartial => failedSources.isNotEmpty;

  @override
  List<Object?> get props => [entries, failedSources, hasMore];
}

/// Reads swap history from both sources and presents one list.
///
/// KDF keeps routed and atomic swaps in separate stores with separate shapes,
/// so merging them is the app's job. Deliberately tolerant of a source being
/// unavailable: a routed-history outage must not blank the atomic swaps a user
/// has been running for years, and vice versa.
class SwapHistoryRepository {
  /// Creates a repository over the routed manager and an atomic reader.
  SwapHistoryRepository({
    required RoutedSwapManager routedSwaps,
    required AtomicSwapHistoryReader atomicHistory,
    required SwapNetworks Function() networks,
    required AssetId? Function(String ticker) resolveAsset,
  }) : _routedSwaps = routedSwaps,
       _atomicHistory = atomicHistory,
       _networks = networks,
       _resolveAsset = resolveAsset;

  final RoutedSwapManager _routedSwaps;
  final AtomicSwapHistoryReader _atomicHistory;
  final SwapNetworks Function() _networks;
  final AssetId? Function(String ticker) _resolveAsset;

  /// Swaps matching [filter], newest first: the most recent [limit] from each
  /// source, merged.
  Future<SwapActivityPage> load({
    required SwapActivityFilter filter,
    int limit = 25,
  }) async {
    final failed = <SwapLiquiditySource>{};
    final networks = _networks();

    final routedFuture = _routed(filter, limit, networks).catchError((
      Object _,
    ) {
      failed.add(SwapLiquiditySource.routed);
      return (entries: <SwapExecutionSnapshot>[], hasMore: false);
    });
    final atomicFuture = _atomic(limit, networks).catchError((Object _) {
      failed.add(SwapLiquiditySource.atomic);
      return (entries: <SwapExecutionSnapshot>[], hasMore: false);
    });
    final routed = await routedFuture;
    final atomic = await atomicFuture;

    final entries = [
      ...routed.entries,
      ...atomic.entries,
    ].where((entry) => matches(entry, filter)).toList()..sort(byNewest);

    return SwapActivityPage(
      entries: entries,
      failedSources: failed,
      hasMore: routed.hasMore || atomic.hasMore,
    );
  }

  /// Whether [entry] belongs under [filter].
  static bool matches(
    SwapExecutionSnapshot entry,
    SwapActivityFilter filter,
  ) => switch (filter) {
    SwapActivityFilter.active => !entry.isTerminal,
    SwapActivityFilter.attention => entry.isTerminal && entry.needsAttention,
    SwapActivityFilter.completed => entry.isTerminal && !entry.needsAttention,
  };

  /// Newest first; a swap without a start time sorts as newest, since only a
  /// just-started swap lacks one.
  static int byNewest(SwapExecutionSnapshot a, SwapExecutionSnapshot b) {
    final aTime = a.createdAt;
    final bTime = b.createdAt;
    if (aTime == null && bTime == null) return a.id.compareTo(b.id);
    if (aTime == null) return -1;
    if (bTime == null) return 1;
    final byTime = bTime.compareTo(aTime);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }

  Future<({List<SwapExecutionSnapshot> entries, bool hasMore})> _routed(
    SwapActivityFilter filter,
    int limit,
    SwapNetworks networks,
  ) async {
    if (filter == SwapActivityFilter.active) {
      final running = await _routedSwaps.inFlight();
      return (
        entries: [
          for (final progress in running)
            routedSnapshotFrom(progress, networks: networks),
        ],
        hasMore: false,
      );
    }
    final page = await _routedSwaps.history(
      filter: RoutedSwapHistoryFilter.terminal,
      limit: limit,
    );
    return (
      entries: [
        for (final progress in page.entries)
          routedSnapshotFrom(progress, networks: networks),
      ],
      hasMore: page.hasMore,
    );
  }

  Future<({List<SwapExecutionSnapshot> entries, bool hasMore})> _atomic(
    int limit,
    SwapNetworks networks,
  ) async {
    final page = await _atomicHistory(limit: limit, page: 1);
    return (
      entries: [
        for (final swap in page.swaps)
          atomicSnapshotFromSwap(
            swap,
            networks: networks,
            resolveAsset: _resolveAsset,
          ),
      ],
      hasMore: page.hasMore,
    );
  }
}
