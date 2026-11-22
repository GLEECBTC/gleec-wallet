import 'dart:async';

import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';

/// Facts shared by the progress screen, wallet summary and receipt. A quote
/// amount is never promoted to a measured receipt by the presentation layer.
class SwapExecutionPresentation {
  const SwapExecutionPresentation(this.snapshot);

  final SwapExecutionSnapshot snapshot;

  AssetId? get receivedAsset =>
      snapshot.outcome?.receivedAsset ??
      (snapshot.isSuccess ? snapshot.to : null);

  bool get hasSourceBroadcast =>
      snapshot.fundsMovement == SwapFundsMovement.sent ||
      snapshot.evidence.sourceTxHash != null;

  /// A stage alone must not say that the asset is on its way when the
  /// snapshot has no evidence of the source transaction leaving the wallet.
  bool get awaitingBroadcastEvidence =>
      !snapshot.isTerminal &&
      snapshot.stage == SwapProgressStage.awaitingDelivery &&
      !hasSourceBroadcast;

  bool get canViewReceivedAsset => snapshot.isSuccess && receivedAsset != null;

  bool visibleOnWallet({required bool seen}) =>
      !snapshot.isTerminal ||
      (!seen && (snapshot.isSuccess || snapshot.needsAttention));
}

enum SwapReceiptBalanceStatus { updating, current, unavailable }

/// Session-only presentation acknowledgements. Execution and polling remain
/// owned by [registry]; this object never copies or persists their snapshots.
class SwapPresentationSession {
  SwapPresentationSession({
    required this.registry,
    required Future<bool> Function(SwapExecutionSnapshot) refreshBalances,
  }) : _refreshBalances = refreshBalances {
    _subscription = registry.executions.listen((snapshots) {
      for (final snapshot in snapshots) {
        if (registry.snapshotOf(snapshot.id) != snapshot) continue;
        if (snapshot.isSuccess) unawaited(refreshReceipt(snapshot));
      }
      _notify();
    });
  }

  final SwapExecutionRegistry registry;
  final Future<bool> Function(SwapExecutionSnapshot) _refreshBalances;
  late final StreamSubscription<List<SwapExecutionSnapshot>> _subscription;
  final _changes = StreamController<int>.broadcast();
  int _revision = 0;
  final Set<String> _seen = {};
  final Set<Object> _moments = {};
  final Set<Object> _notices = {};
  final Map<String, SwapReceiptBalanceStatus> _balances = {};
  final Map<String, Future<void>> _refreshing = {};
  int _generation = 0;
  bool _disposed = false;
  Object _sessionIdentity = Object();

  /// Changes when the wallet changes, so deferred UI cannot cross sessions.
  Object get sessionIdentity => _sessionIdentity;

  Stream<int> get changes => _changes.stream;

  List<SwapExecutionSnapshot> get walletEntries => [
    for (final snapshot in registry.current)
      if (SwapExecutionPresentation(snapshot)
          .visibleOnWallet(seen: _seen.contains(snapshot.id)))
        snapshot,
  ];

  SwapReceiptBalanceStatus? balanceStatus(String id) => _balances[id];

  /// Seeing a running swap does not acknowledge a future outcome.
  void markSeen(SwapExecutionSnapshot snapshot) {
    if (!snapshot.isTerminal || !_seen.add(snapshot.id)) return;
    registry.acknowledge(snapshot.id);
    _notify();
  }

  /// Only genuine new events call this; replayed snapshots never do.
  bool claimMoment(SwapExecutionSnapshot snapshot) =>
      _moments.add((snapshot.id, snapshot.outcome?.kind ?? snapshot.stage));

  bool claimNotice(SwapExecutionNotice notice) =>
      _notices.add((notice.snapshot.id, notice.kind));

  /// One bounded fresh read per completed swap. A failed read is retried only
  /// by an explicit action, never by an animation or a widget rebuild.
  Future<void> refreshReceipt(
    SwapExecutionSnapshot snapshot, {
    bool retry = false,
  }) {
    if (_disposed || !snapshot.isSuccess) return Future<void>.value();
    final pending = _refreshing[snapshot.id];
    if (pending != null) return pending;
    if (!retry && _balances.containsKey(snapshot.id)) {
      return Future<void>.value();
    }
    final generation = _generation;
    _balances[snapshot.id] = SwapReceiptBalanceStatus.updating;
    _notify();
    final work = () async {
      var current = false;
      try {
        current = await _refreshBalances(snapshot)
            .timeout(const Duration(seconds: 15));
      } on Object {
        // The receipt is still complete; only the balance read is unavailable.
      }
      if (_disposed || generation != _generation) return;
      _balances[snapshot.id] = current
          ? SwapReceiptBalanceStatus.current
          : SwapReceiptBalanceStatus.unavailable;
      _refreshing.remove(snapshot.id);
      _notify();
    }();
    _refreshing[snapshot.id] = work;
    return work;
  }

  void reset() {
    _generation++;
    _sessionIdentity = Object();
    _seen.clear();
    _moments.clear();
    _notices.clear();
    _balances.clear();
    _refreshing.clear();
    _notify();
  }

  void _notify() {
    if (!_disposed) _changes.add(++_revision);
  }

  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    await _subscription.cancel();
    await _changes.close();
  }
}
