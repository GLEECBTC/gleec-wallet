import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// Where a running swap has got to, whichever source is filling it.
enum SwapPhase {
  /// Pricing, allowance checks, order submission. Nothing irreversible.
  preparing,

  /// An ERC-20 approval is on-chain.
  approving,

  /// Signing locally.
  signing,

  /// Handed to the network. No longer stoppable.
  sending,

  /// Waiting for on-chain confirmation.
  confirming,

  /// Following a bridge, or waiting for an atomic counterparty.
  settling,

  /// Stopped. Check the outcome — stopped is not succeeded.
  finished,

  /// Failed.
  failed,

  /// Unrecognised.
  unknown,
}

/// A snapshot of a running or finished swap.
class UnifiedSwapProgress {
  const UnifiedSwapProgress({
    required this.id,
    required this.source,
    required this.phase,
    required this.canCancel,
    this.isSuccess = false,
    this.headline,
    this.detail,
    this.receivedAmount,
    this.receivedToken,
    this.fundsUntouched = false,
    this.providerDetail,
    this.explorerUrl,
  });

  /// Builds a snapshot from the routed SDK's own progress type.
  factory UnifiedSwapProgress.fromRouted(RoutedSwapProgress progress) {
    final receipt = progress.receipt;
    return UnifiedSwapProgress(
      id: progress.uuid,
      source: SwapLiquiditySource.routed,
      phase: switch (progress.phase) {
        RoutedSwapPhase.preparing => SwapPhase.preparing,
        RoutedSwapPhase.approving => SwapPhase.approving,
        RoutedSwapPhase.signing => SwapPhase.signing,
        RoutedSwapPhase.sending => SwapPhase.sending,
        RoutedSwapPhase.confirming => SwapPhase.confirming,
        RoutedSwapPhase.bridging => SwapPhase.settling,
        RoutedSwapPhase.finished => SwapPhase.finished,
        RoutedSwapPhase.failed => SwapPhase.failed,
        RoutedSwapPhase.unknown => SwapPhase.unknown,
      },
      canCancel: progress.canCancel,
      isSuccess: progress.isSuccess,
      headline: switch (receipt?.outcome.wire) {
        'completed' => 'You received ${receipt!.amount} ${receipt.tokenLabel}',
        'partial' => 'Partly filled',
        'refunded' => 'Swap refunded',
        _ => null,
      },
      detail: switch (receipt?.outcome.wire) {
        'partial' =>
          'You received ${receipt!.amount} ${receipt.tokenLabel}, which is '
              'not the full amount you asked for.',
        'refunded' =>
          'The swap did not happen. ${receipt!.amount} ${receipt.tokenLabel} '
              'was returned to you.',
        _ => progress.failure?.message,
      },
      receivedAmount: receipt?.amount,
      receivedToken: receipt?.tokenLabel,
      fundsUntouched: progress.failure?.fundsUntouched ?? false,
      providerDetail: progress.providerStatusDetail,
      explorerUrl: progress.explorerUrl,
    );
  }

  /// The durable id. A uuid from either source.
  final String id;

  /// Which source is filling this.
  final SwapLiquiditySource source;

  /// Where it has got to.
  final SwapPhase phase;

  /// Whether stopping it would currently be accepted.
  final bool canCancel;

  /// Whether it delivered what was asked for.
  ///
  /// Never inferred from [phase]: a refund and a partial fill are both
  /// finished and neither is a success.
  final bool isSuccess;

  /// Terminal headline, when there is one.
  final String? headline;

  /// Supporting detail.
  final String? detail;

  /// What actually arrived.
  final Decimal? receivedAmount;

  /// The token that arrived.
  final String? receivedToken;

  /// Whether nothing was broadcast, so the balance is unchanged.
  final bool fundsUntouched;

  /// Opaque provider progress text.
  final String? providerDetail;

  /// An explorer link for the swap.
  final String? explorerUrl;

  /// Whether the swap has stopped, either way.
  bool get isTerminal =>
      phase == SwapPhase.finished || phase == SwapPhase.failed;
}

/// A running swap the caller can follow and possibly stop.
abstract interface class SwapExecutionHandle {
  /// The durable id.
  String get id;

  /// Progress until terminal.
  Stream<UnifiedSwapProgress> get progress;

  /// Stops the swap if that is still possible.
  Future<void> cancel();
}

/// Starts swaps for one liquidity source.
abstract interface class SwapExecutor {
  /// Which source this executes for.
  SwapLiquiditySource get source;

  /// Begins executing [quote].
  Future<SwapExecutionHandle> start(SwapQuote quote);
}

/// Executes routed swaps through the SDK.
class RoutedSwapExecutor implements SwapExecutor {
  /// Creates an executor over [manager].
  const RoutedSwapExecutor(this.manager);

  /// The SDK manager.
  final RoutedSwapManager manager;

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.routed;

  @override
  Future<SwapExecutionHandle> start(SwapQuote quote) async {
    final offer = quote.payload;
    if (offer is! RoutedSwapOffer) {
      throw StateError('This offer can no longer be executed. Re-quote first.');
    }
    return _RoutedHandle(await manager.start(offer));
  }
}

class _RoutedHandle implements SwapExecutionHandle {
  _RoutedHandle(this._handle);

  final RoutedSwapHandle _handle;

  @override
  String get id => _handle.uuid;

  @override
  Stream<UnifiedSwapProgress> get progress =>
      _handle.progress.map(UnifiedSwapProgress.fromRouted);

  @override
  Future<void> cancel() => _handle.cancel();
}

/// Executes atomic swaps by placing a fill-or-kill taker order.
///
/// Fill-or-kill is the right order type for a quoted swap: the user was shown
/// a price for a specific size, and a partially filled or resting order is a
/// different trade from the one they agreed to.
class AtomicSwapExecutor implements SwapExecutor {
  /// Creates an executor over the DEX repository and trading manager.
  const AtomicSwapExecutor({
    required DexRepository dexRepository,
    required TradingManager trading,
  }) : _dex = dexRepository,
       _trading = trading;

  final DexRepository _dex;
  final TradingManager _trading;

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.atomic;

  @override
  Future<SwapExecutionHandle> start(SwapQuote quote) async {
    final plan = quote.payload;
    if (plan is! AtomicSwapPlan) {
      throw StateError('This offer can no longer be executed. Re-quote first.');
    }

    final response = await _dex.sell(
      SellRequest(
        base: plan.base.id,
        rel: plan.rel.id,
        volume: Rational.parse(plan.volume.toString()),
        price: Rational.parse(plan.price.toString()),
        orderType: SellBuyOrderType.fillOrKill,
      ),
    );

    final error = response.error;
    if (error != null) throw StateError(error.message);

    final uuid = response.result?.uuid;
    if (uuid == null) {
      throw StateError('The order was accepted but returned no reference.');
    }

    return _AtomicHandle(uuid: uuid, trading: _trading);
  }
}

class _AtomicHandle implements SwapExecutionHandle {
  _AtomicHandle({required String uuid, required TradingManager trading})
    : id = uuid,
      _trading = trading;

  @override
  final String id;

  final TradingManager _trading;

  @override
  Stream<UnifiedSwapProgress> get progress =>
      _trading.watchSwapStatus(uuid: id).map(_toProgress);

  /// An atomic taker order cannot be recalled once it is matched, and KDF
  /// exposes no cancel for an in-flight swap — only for a resting order, which
  /// a fill-or-kill never becomes.
  @override
  Future<void> cancel() async =>
      throw StateError('An atomic swap cannot be cancelled once placed.');

  UnifiedSwapProgress _toProgress(SwapInfo info) {
    if (!info.isComplete) {
      return UnifiedSwapProgress(
        id: id,
        source: SwapLiquiditySource.atomic,
        phase: SwapPhase.settling,
        canCancel: false,
        detail: 'Waiting for the other side to complete their part.',
      );
    }

    final succeeded = info.isSuccessful;
    return UnifiedSwapProgress(
      id: id,
      source: SwapLiquiditySource.atomic,
      phase: succeeded ? SwapPhase.finished : SwapPhase.failed,
      canCancel: false,
      isSuccess: succeeded,
      headline: succeeded
          ? 'You received ${info.makerAmount} ${info.makerCoin}'
          : 'Swap did not complete',
      // Atomic swaps have their own recovery machinery and a much richer
      // event log than this surface renders. Pointing at it beats paraphrasing
      // a failure whose detail lives elsewhere.
      detail: succeeded
          ? null
          : 'See Advanced for the full swap log and any recovery options.',
      receivedAmount: succeeded ? Decimal.tryParse(info.makerAmount) : null,
      receivedToken: succeeded ? info.makerCoin : null,
    );
  }
}
