import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/analytics/events/transaction_events.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// Reports the unified swap flow on the existing `swap_initiated`,
/// `swap_success` and `swap_failure` events.
///
/// Adds only categories — how the swap completes, how it ended, how many
/// steps it took, how long — never an address, a hash or a raw payload.
class SwapAnalyticsReporter {
  SwapAnalyticsReporter({
    required SwapExecutionRegistry registry,
    required void Function(AnalyticsEventData event) log,
    required String Function() walletType,
  }) : _log = log,
       _walletType = walletType {
    _subscriptions
      ..add(registry.started.listen(_onStarted))
      ..add(registry.updates.listen(_onUpdate));
  }

  final void Function(AnalyticsEventData event) _log;
  final String Function() _walletType;
  final List<StreamSubscription<SwapExecutionSnapshot>> _subscriptions = [];

  /// Swaps seen running this session. Only these report an outcome, so
  /// opening an old swap in Activity never re-reports it.
  final Set<String> _running = {};

  void _onStarted(SwapExecutionSnapshot snapshot) {
    _running.add(snapshot.id);
    _log(
      SwapInitiatedEventData(
        asset: snapshot.fromTicker,
        secondaryAsset: snapshot.toTicker,
        network: _network(snapshot.from),
        secondaryNetwork: _network(snapshot.to),
        hdType: _walletType(),
        routeCategory: routeCategory(snapshot),
        stageCount: snapshot.stages.isEmpty ? null : snapshot.stages.length,
      ),
    );
  }

  void _onUpdate(SwapExecutionSnapshot snapshot) {
    if (!snapshot.isTerminal) {
      _running.add(snapshot.id);
      return;
    }
    if (!_running.remove(snapshot.id)) return;

    final outcome = snapshot.outcome!;
    final started = snapshot.createdAt;
    final finished = snapshot.finishedAt ?? snapshot.updatedAt;
    final durationMs = started == null || finished == null
        ? null
        : finished.difference(started).inMilliseconds;
    final stageCount = snapshot.stages.isEmpty ? null : snapshot.stages.length;

    if (outcome.isSuccess) {
      _log(
        SwapSucceededEventData(
          asset: snapshot.fromTicker,
          secondaryAsset: snapshot.toTicker,
          network: _network(snapshot.from),
          secondaryNetwork: _network(snapshot.to),
          amount: (snapshot.sellAmount ?? Decimal.zero).toDouble(),
          fee: _gasSpent(snapshot),
          hdType: _walletType(),
          durationMs: durationMs,
          routeCategory: routeCategory(snapshot),
          stageCount: stageCount,
        ),
      );
      return;
    }
    _log(
      SwapFailedEventData(
        asset: snapshot.fromTicker,
        secondaryAsset: snapshot.toTicker,
        network: _network(snapshot.from),
        secondaryNetwork: _network(snapshot.to),
        failureStage: '${snapshot.source.name}_execution',
        failureCategory: switch (outcome.failure?.reason) {
          final SwapFailureReason reason => failureCategory(reason),
          null => null,
        },
        hdType: _walletType(),
        durationMs: durationMs,
        routeCategory: routeCategory(snapshot),
        outcomeCategory: outcomeCategory(outcome.kind),
        stageCount: stageCount,
      ),
    );
  }

  /// `atomic`, `same_chain` or `cross_chain`.
  static String routeCategory(SwapExecutionSnapshot snapshot) =>
      switch (snapshot.routeKind) {
        SwapRouteKind.direct => 'atomic',
        SwapRouteKind.sameChain => 'same_chain',
        SwapRouteKind.crossChain => 'cross_chain',
      };

  /// The analytics name of an outcome.
  static String outcomeCategory(SwapOutcomeKind kind) => switch (kind) {
    SwapOutcomeKind.completed => 'completed',
    SwapOutcomeKind.partialBelowMinimum => 'partial_below_minimum',
    SwapOutcomeKind.partialOtherToken => 'partial_other_token',
    SwapOutcomeKind.refunded => 'refunded',
    SwapOutcomeKind.cancelled => 'cancelled',
    SwapOutcomeKind.noMatch => 'no_match',
    SwapOutcomeKind.failed => 'failed',
  };

  /// The analytics name of why a swap failed.
  static String failureCategory(SwapFailureReason reason) => switch (reason) {
    SwapFailureReason.priceMoved => 'price_moved',
    SwapFailureReason.insufficientBalance => 'insufficient_funds',
    SwapFailureReason.approvalFailed => 'approval_failed',
    SwapFailureReason.reverted => 'reverted',
    SwapFailureReason.notConfirmed => 'not_confirmed',
    SwapFailureReason.walletRejected => 'wallet_rejected',
    SwapFailureReason.routeFailed => 'route_failed',
    SwapFailureReason.safetyCheck => 'safety_check',
    SwapFailureReason.quoteUnavailable => 'quote_unavailable',
    SwapFailureReason.restarted => 'restarted',
    SwapFailureReason.exchangeFailed => 'exchange_failed',
    SwapFailureReason.internal => 'internal',
    SwapFailureReason.unknown => 'unknown',
  };

  static String _network(AssetId? asset) =>
      asset == null ? 'unknown' : asset.subClass.formatted;

  /// Gas paid, when it was all paid in one coin; zero otherwise, since
  /// amounts in different coins do not add up.
  static double _gasSpent(SwapExecutionSnapshot snapshot) {
    final gas = snapshot.evidence.gasSpent;
    if (gas.isEmpty || gas.map((g) => g.ticker).toSet().length != 1) return 0;
    return gas
        .fold<Decimal>(Decimal.zero, (sum, g) => sum + g.amount)
        .toDouble();
  }

  /// Stops reporting.
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}
