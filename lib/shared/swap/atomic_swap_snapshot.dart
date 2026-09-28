part of 'atomic_swap_execution.dart';

/// The events marking one side's steps through an atomic swap's log.
typedef _AtomicSide = ({
  String? fee,
  String sending,
  List<String> confirming,
  String sent,
  String received,
  List<String> refunding,
  List<String> refunded,
});

const _AtomicSide _taker = (
  fee: 'TakerFeeSent',
  sending: 'TakerFeeSent',
  confirming: [
    'MakerPaymentReceived',
    'MakerPaymentWaitConfirmStarted',
    'MakerPaymentValidatedAndConfirmed',
  ],
  sent: 'TakerPaymentSent',
  received: 'MakerPaymentSpent',
  refunding: ['TakerPaymentWaitRefundStarted', 'TakerPaymentRefundStarted'],
  refunded: [
    'TakerPaymentRefunded',
    'TakerPaymentRefundedByWatcher',
    'TakerPaymentRefundFinished',
  ],
);

/// A maker pays no fee, and pays first: once the taker's fee checks out.
const _AtomicSide _maker = (
  fee: null,
  sending: 'TakerFeeValidated',
  confirming: [],
  sent: 'MakerPaymentSent',
  received: 'TakerPaymentSpent',
  refunding: ['MakerPaymentWaitRefundStarted', 'MakerPaymentRefundStarted'],
  refunded: ['MakerPaymentRefunded', 'MakerPaymentRefundFinished'],
);

_AtomicSide _sideOf(Swap swap) => swap.isTaker ? _taker : _maker;

/// Describes an atomic swap at [stage], before or without its event log.
SwapExecutionSnapshot atomicSnapshot({
  required String uuid,
  required SwapProgressStage stage,
  required SwapNetworks networks,
  required AssetId? Function(String ticker) resolveAsset,
  bool canCancel = false,
  SwapFundsMovement movement = SwapFundsMovement.none,
  SwapExecutionOutcome? outcome,
  SwapQuote? accepted,
  Swap? swap,
}) {
  final from =
      accepted?.from ?? (swap == null ? null : resolveAsset(swap.sellCoin));
  final to = accepted?.to ?? (swap == null ? null : resolveAsset(swap.buyCoin));
  final side = swap == null ? null : _sideOf(swap);
  String? hashOf(String? type) => swap?.events
      .where((e) => e.event.type == type)
      .map((e) => e.event.data?.txHash)
      .whereType<String>()
      .firstOrNull;
  final events = swap?.events ?? const <SwapEventItem>[];
  DateTime? at(int? millis) => millis == null || millis == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(millis);

  return SwapExecutionSnapshot(
    id: uuid,
    source: SwapLiquiditySource.atomic,
    routeKind: SwapRouteKind.direct,
    from: from,
    fromTicker: from?.id ?? swap?.sellCoin ?? '',
    to: to,
    toTicker: to?.id ?? swap?.buyCoin ?? '',
    sellAmount:
        accepted?.sellAmount ??
        (swap == null ? null : _decimalOf(swap.sellAmount)),
    expectedReceive:
        accepted?.expectedReceive ??
        (swap == null ? null : _decimalOf(swap.buyAmount)),
    minimumReceive:
        accepted?.guaranteedReceive ??
        (swap == null ? null : _decimalOf(swap.buyAmount)),
    fromAddress: accepted?.fromAddress,
    toAddress: accepted?.toAddress,
    stage: outcome == null ? stage : null,
    outcome: outcome,
    fundsMovement: movement,
    canCancel: outcome == null && canCancel,
    stages:
        accepted?.stages ??
        [
          const SwapRouteStage(kind: SwapRouteStageKind.prepare),
          if (from != null)
            SwapRouteStage(
              kind: SwapRouteStageKind.send,
              network: networks.networkOf(from),
              asset: from,
            ),
          if (to != null) ...[
            SwapRouteStage(
              kind: SwapRouteStageKind.exchange,
              network: networks.networkOf(to),
              asset: to,
            ),
            SwapRouteStage(
              kind: SwapRouteStageKind.receive,
              network: networks.networkOf(to),
              asset: to,
            ),
          ],
        ],
    createdAt: at(events.firstOrNull?.timestamp),
    updatedAt: at(events.lastOrNull?.timestamp),
    finishedAt: outcome == null ? null : at(events.lastOrNull?.timestamp),
    evidence: SwapEvidence(
      executionId: uuid,
      sourceTxHash: hashOf(side?.sent),
      destinationTxHash: hashOf(side?.received),
      rawState: events.lastOrNull?.event.type,
      errorType: events
          .map((e) => e.event.type)
          .where((type) => swap?.errorEvents.contains(type) ?? false)
          .firstOrNull,
    ),
  );
}

/// Describes an atomic [swap] from its event log.
///
/// A taker's log runs Started, Negotiated, TakerFeeSent, MakerPaymentReceived
/// (then its confirmation), TakerPaymentSent, MakerPaymentSpent, Finished; a
/// maker's runs Started, Negotiated, TakerFeeValidated, MakerPaymentSent,
/// TakerPaymentReceived (then its confirmation), TakerPaymentSpent, Finished.
/// A failure adds error events and, once the payment has left, the refund
/// events. KDF closes every swap, successful or not, with Finished.
SwapExecutionSnapshot atomicSnapshotFromSwap(
  Swap swap, {
  required SwapNetworks networks,
  required AssetId? Function(String ticker) resolveAsset,
  SwapQuote? accepted,
}) {
  final side = _sideOf(swap);
  final types = swap.events.map((e) => e.event.type).toList();
  bool has(String? type) => types.contains(type);
  final failed = types.any(swap.errorEvents.contains);
  final paid = has(side.sent);
  final refunded = side.refunded.any(has);
  final refunding = side.refunding.any(has);

  final movement = paid
      ? SwapFundsMovement.sent
      : has(side.fee)
      ? SwapFundsMovement.feesOnly
      : SwapFundsMovement.none;

  SwapExecutionSnapshot snapshot(
    SwapProgressStage stage, {
    SwapFundsMovement? movementOverride,
    SwapExecutionOutcome? outcome,
  }) => atomicSnapshot(
    uuid: swap.uuid,
    stage: stage,
    movement: movementOverride ?? movement,
    outcome: outcome,
    accepted: accepted,
    swap: swap,
    networks: networks,
    resolveAsset: resolveAsset,
  );

  if (has('Finished')) {
    if (!failed) {
      return snapshot(
        SwapProgressStage.exchanging,
        movementOverride: SwapFundsMovement.sent,
        outcome: SwapExecutionOutcome(
          kind: SwapOutcomeKind.completed,
          receivedAmount: _decimalOf(swap.buyAmount),
          receivedAsset: accepted?.to ?? resolveAsset(swap.buyCoin),
        ),
      );
    }
    if (refunded) {
      return snapshot(
        SwapProgressStage.refunding,
        movementOverride: SwapFundsMovement.sent,
        outcome: SwapExecutionOutcome(
          kind: SwapOutcomeKind.refunded,
          receivedAsset: accepted?.from ?? resolveAsset(swap.sellCoin),
        ),
      );
    }
    return snapshot(
      SwapProgressStage.exchanging,
      movementOverride: paid ? SwapFundsMovement.uncertain : movement,
      outcome: SwapExecutionOutcome(
        kind: SwapOutcomeKind.failed,
        failure: SwapExecutionFailure(
          reason: SwapFailureReason.exchangeFailed,
          // Before the payment left, trying again is safe; after it, the
          // swap's own recovery in Advanced is the way to the funds.
          nextStep: paid ? SwapNextStep.contactSupport : SwapNextStep.retry,
          retryable: !paid,
          detail: types.where(swap.errorEvents.contains).join(', '),
        ),
      ),
    );
  }

  final stage = refunding
      ? SwapProgressStage.refunding
      : has(side.received) || paid
      ? SwapProgressStage.exchanging
      : side.confirming.any(has)
      ? SwapProgressStage.confirming
      : has(side.sending)
      ? SwapProgressStage.sending
      : SwapProgressStage.preparing;
  return snapshot(stage);
}

Decimal _decimalOf(Rational value) =>
    value.toDecimal(scaleOnInfinitePrecision: 18);
