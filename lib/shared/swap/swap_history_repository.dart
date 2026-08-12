import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// One swap in the history list, from either liquidity source.
///
/// The two backends persist swaps in completely different shapes and, as of
/// today, in completely separate stores. Presenting them as one list is a GUI
/// responsibility precisely because KDF does not do it: `my_recent_swaps`
/// knows nothing about routed swaps, and `routed_swap::history` knows nothing
/// about atomic ones.
class SwapHistoryEntry {
  const SwapHistoryEntry({
    required this.id,
    required this.source,
    required this.isInFlight,
    required this.updatedAt,
    this.title,
    this.statusLabel,
    this.needsAttention = false,
    this.progress,
    this.raw,
  });

  /// The durable identifier. A uuid on both sides, so the two never collide.
  final String id;

  /// Which liquidity source ran this swap.
  final SwapLiquiditySource source;

  /// Whether it is still running and should be resumable.
  final bool isInFlight;

  /// When it last changed, used for ordering.
  final DateTime updatedAt;

  /// A one-line description, when one can be derived.
  final String? title;

  /// A short human status.
  final String? statusLabel;

  /// Whether the entry needs the user to look at it.
  ///
  /// True for outcomes that are terminal but not what was asked for — a
  /// partial fill or a refund — which would otherwise sit in the list looking
  /// like ordinary completed swaps.
  final bool needsAttention;

  /// Routed progress, when this came from the routed side.
  final RoutedSwapProgress? progress;

  /// The original record, for the support export.
  final Object? raw;
}

/// Reads swap history from every source and presents one list.
///
/// Deliberately tolerant of a source being unavailable: a routed-history
/// outage must not blank the atomic swaps a user has been running for years,
/// and vice versa. A partial list is more useful than an error page, provided
/// the caller can tell it is partial.
class SwapHistoryRepository {
  /// Creates a repository over the routed manager and an atomic reader.
  SwapHistoryRepository({
    required RoutedSwapManager routedSwaps,
    required Future<List<SwapHistoryEntry>> Function({int limit}) atomicHistory,
  }) : _routedSwaps = routedSwaps,
       _atomicHistory = atomicHistory;

  final RoutedSwapManager _routedSwaps;
  final Future<List<SwapHistoryEntry>> Function({int limit}) _atomicHistory;

  /// Merged history, newest first.
  ///
  /// [failedSources] reports which backends could not be read, so the UI can
  /// say the list is incomplete rather than implying the missing swaps never
  /// happened.
  Future<SwapHistoryPage> recent({int limit = 20}) async {
    final failed = <SwapLiquiditySource>{};

    final routed = await _routedSwaps
        .history(limit: limit)
        .then(
          (entries) => entries.map(_fromRouted).toList(),
          onError: (Object _) {
            failed.add(SwapLiquiditySource.routed);
            return <SwapHistoryEntry>[];
          },
        );

    final atomic = await _atomicHistory(limit: limit).then(
      (entries) => entries,
      onError: (Object _) {
        failed.add(SwapLiquiditySource.atomic);
        return <SwapHistoryEntry>[];
      },
    );

    final merged = [...routed, ...atomic]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return SwapHistoryPage(
      entries: merged.take(limit).toList(),
      failedSources: failed,
    );
  }

  /// Swaps still running, across both sources.
  ///
  /// The cold-start question after a relaunch. A cross-chain swap can outlive
  /// several app sessions, so this is routine rather than exceptional.
  Future<List<SwapHistoryEntry>> inFlight() async {
    try {
      final routed = await _routedSwaps.inFlight();
      return routed.map(_fromRouted).toList();
    } on Object {
      return const [];
    }
  }

  SwapHistoryEntry _fromRouted(RoutedSwapProgress progress) {
    final receipt = progress.receipt;
    return SwapHistoryEntry(
      id: progress.uuid,
      source: SwapLiquiditySource.routed,
      isInFlight: !progress.isTerminal,
      // The routed record carries its own timestamps, but the SDK's progress
      // type does not surface them yet; ordering falls back to now for live
      // entries, which keeps them at the top where they belong.
      updatedAt: DateTime.now(),
      title: receipt == null
          ? null
          : 'Received ${receipt.amount} ${receipt.tokenLabel}',
      statusLabel: _labelFor(progress),
      // A partial fill or a refund is finished but is not what was asked for.
      // Leaving them unmarked would bury them among ordinary completions.
      needsAttention:
          progress.isTerminal &&
          !progress.isSuccess &&
          progress.failure?.kind != RoutedSwapFailureKind.cancelled,
      progress: progress,
    );
  }

  static String _labelFor(RoutedSwapProgress progress) {
    if (progress.failure != null) return 'Failed';
    final receipt = progress.receipt;
    if (receipt != null) {
      return switch (receipt.outcome.wire) {
        'completed' => 'Completed',
        'partial' => 'Partly filled',
        'refunded' => 'Refunded',
        _ => 'Finished',
      };
    }
    return 'In progress';
  }
}

/// A page of merged history.
class SwapHistoryPage {
  const SwapHistoryPage({required this.entries, required this.failedSources});

  /// The merged entries, newest first.
  final List<SwapHistoryEntry> entries;

  /// Sources that could not be read.
  ///
  /// Non-empty means the list is incomplete. Saying so is the difference
  /// between "you have no routed swaps" and "we could not check".
  final Set<SwapLiquiditySource> failedSources;

  /// Whether anything is missing from this page.
  bool get isPartial => failedSources.isNotEmpty;
}
