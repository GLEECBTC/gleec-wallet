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
  DateTime? delayedSince,
  DateTime? placedAt,
  DateTime? finishedAt,
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
    createdAt: at(events.firstOrNull?.timestamp) ?? placedAt,
    updatedAt: at(events.lastOrNull?.timestamp),
    finishedAt: outcome == null
        ? null
        : at(events.lastOrNull?.timestamp) ?? finishedAt,
    delayedSince: outcome == null ? delayedSince : null,
    refundUnlocksAt: outcome == null && stage == SwapProgressStage.refunding
        ? _refundLock(swap)
        : null,
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
///
/// Given [now], an overdue log reads as delayed; see [_overdueSince].
SwapExecutionSnapshot atomicSnapshotFromSwap(
  Swap swap, {
  required SwapNetworks networks,
  required AssetId? Function(String ticker) resolveAsset,
  SwapQuote? accepted,
  DateTime? now,
  DateTime? delayedSince,
  DateTime? placedAt,
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
  final delay = _earlier(
    delayedSince,
    now == null ? null : _overdueSince(swap, now),
  );

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
    delayedSince: delay,
    placedAt: placedAt,
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

/// How long after a deadline KDF has to log the event that ends the wait:
/// it checks every 10–15 s, and a node can be slow to answer.
const _overdueGrace = Duration(minutes: 10);

/// The deadline a taker's [swap] has passed without moving on, if any.
///
/// Its Started event records when its two long waits end: for the maker's
/// payment to arrive and confirm (`maker_payment_wait`), then for its own
/// payment to be spent (`taker_payment_lock`). KDF ends each by then with an
/// event either way, so a log still waiting is one KDF is not running — after
/// a restart it holds a swap until both coins are enabled. The gap since the
/// last event proves nothing alone: a confirmation can take hours.
DateTime? _overdueSince(Swap swap, DateTime now) {
  final types = swap.events.map((e) => e.event.type).toSet();
  if (!swap.isTaker ||
      types.contains('Finished') ||
      types.any(swap.errorEvents.contains)) {
    return null;
  }
  final started = swap.events
      .where((e) => e.event.type == 'Started')
      .firstOrNull
      ?.event
      .data;
  final seconds = !types.contains('MakerPaymentValidatedAndConfirmed')
      ? started?.makerPaymentWait
      : !types.contains('TakerPaymentSpent')
      ? started?.takerPaymentLock
      : null;
  if (seconds == null || seconds == 0) return null;
  final deadline = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  return now.isAfter(deadline.add(_overdueGrace)) ? deadline : null;
}

/// When [swap]'s own payment can be refunded: the lock its Started event
/// records, in seconds, for whichever side this wallet took.
DateTime? _refundLock(Swap? swap) {
  if (swap == null) return null;
  final started = swap.events
      .where((e) => e.event.type == 'Started')
      .firstOrNull
      ?.event
      .data;
  final seconds = swap.isTaker
      ? started?.takerPaymentLock
      : started?.makerPaymentLock;
  if (seconds == null || seconds == 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

DateTime? _earlier(DateTime? a, DateTime? b) =>
    a == null || (b != null && b.isBefore(a)) ? b : a;

Decimal _decimalOf(Rational value) =>
    value.toDecimal(scaleOnInfinitePrecision: 18);
