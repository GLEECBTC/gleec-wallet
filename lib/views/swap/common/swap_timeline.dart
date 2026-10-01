import 'package:easy_localization/easy_localization.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';

/// The status of one step in a swap's timeline. [refunded] marks where a
/// swap turned back and returned the funds.
enum SwapStepStatus { done, current, error, cancelled, refunded, notStarted }

/// Where a step can be checked: its transaction on an explorer, or the
/// route's own status page.
class SwapTimelineLink {
  const SwapTimelineLink.transaction(this.url) : route = false;
  const SwapTimelineLink.route(this.url) : route = true;

  final Uri url;
  final bool route;
}

/// One step of the timeline, ready to draw.
class SwapTimelineStep {
  const SwapTimelineStep({
    required this.title,
    required this.detail,
    required this.status,
    this.link,
  });

  final String title;
  final String detail;
  final SwapStepStatus status;
  final SwapTimelineLink? link;
}

/// A transaction's page on the explorer for [asset]'s network, when known.
typedef SwapExplorerTx = Uri? Function(AssetId? asset, String hash);

/// Turns a swap's stages and progress into the timeline the prototype draws.
abstract final class SwapTimeline {
  /// The steps of [snapshot], or of a quote's [stages] before it starts.
  /// With [explorer], a step links to its transaction once it has one.
  static List<SwapTimelineStep> of(
    SwapExecutionSnapshot snapshot,
    SwapNetworks networks, {
    SwapExplorerTx? explorer,
  }) {
    final stages = snapshot.stages.isEmpty
        ? _fallbackStages(snapshot)
        : snapshot.stages;
    final statuses = _statuses(snapshot, stages);
    final routeStep = stages.indexWhere(
      (s) =>
          s.kind == SwapRouteStageKind.bridge ||
          s.kind == SwapRouteStageKind.convert,
    );
    return [
      for (var i = 0; i < stages.length; i++)
        _step(
          stages[i],
          statuses[i],
          networks: networks,
          snapshot: snapshot,
          explorer: explorer,
          routeStep: i == routeStep,
        ),
    ];
  }

  /// The steps of a quote, all not yet started, for the review.
  static List<String> describe(SwapQuote quote, SwapNetworks networks) => [
    for (final stage in quote.stages)
      stageTitle(stage, networks: networks, received: false),
  ];

  static List<SwapRouteStage> _fallbackStages(SwapExecutionSnapshot s) => [
    const SwapRouteStage(kind: SwapRouteStageKind.prepare),
    SwapRouteStage(kind: SwapRouteStageKind.send, asset: s.from),
    if (s.source == SwapLiquiditySource.atomic)
      const SwapRouteStage(kind: SwapRouteStageKind.exchange)
    else if (s.routeKind == SwapRouteKind.crossChain)
      SwapRouteStage(kind: SwapRouteStageKind.bridge, asset: s.to)
    else
      SwapRouteStage(kind: SwapRouteStageKind.convert, asset: s.to),
    SwapRouteStage(kind: SwapRouteStageKind.receive, asset: s.to),
  ];

  static int _indexOf(List<SwapRouteStage> stages, SwapRouteStageKind kind) =>
      stages.indexWhere((s) => s.kind == kind);

  static int _firstOf(
    List<SwapRouteStage> stages,
    List<SwapRouteStageKind> kinds,
  ) {
    for (final kind in kinds) {
      final index = _indexOf(stages, kind);
      if (index >= 0) return index;
    }
    return 0;
  }

  /// Where the swap is (or stopped) in [stages].
  static int _position(SwapExecutionSnapshot s, List<SwapRouteStage> stages) {
    const afterSend = [
      SwapRouteStageKind.bridge,
      SwapRouteStageKind.convert,
      SwapRouteStageKind.exchange,
      SwapRouteStageKind.receive,
    ];
    switch (s.stage) {
      case SwapProgressStage.preparing ||
          SwapProgressStage.matching ||
          SwapProgressStage.signing ||
          null:
        return _firstOf(stages, const [SwapRouteStageKind.prepare]);
      case SwapProgressStage.approving:
        final resetting =
            (s.approval?.resetsFirst ?? false) &&
            s.evidence.approvalTxHashes.isEmpty;
        return _firstOf(
          stages,
          resetting
              ? const [
                  SwapRouteStageKind.resetApproval,
                  SwapRouteStageKind.approve,
                ]
              : const [SwapRouteStageKind.approve],
        );
      case SwapProgressStage.sending || SwapProgressStage.confirming:
        return _firstOf(stages, const [SwapRouteStageKind.send]);
      case SwapProgressStage.bridging ||
          SwapProgressStage.awaitingDelivery ||
          SwapProgressStage.refunding ||
          SwapProgressStage.actionRequired:
        return _firstOf(stages, const [
          SwapRouteStageKind.bridge,
          SwapRouteStageKind.convert,
          SwapRouteStageKind.receive,
        ]);
      case SwapProgressStage.exchanging:
        return _firstOf(stages, const [SwapRouteStageKind.exchange]);
      case SwapProgressStage.unknown:
        return s.fundsMovement == SwapFundsMovement.sent
            ? _firstOf(stages, afterSend)
            : _firstOf(stages, const [SwapRouteStageKind.send]);
    }
  }

  static List<SwapStepStatus> _statuses(
    SwapExecutionSnapshot s,
    List<SwapRouteStage> stages,
  ) {
    final outcome = s.outcome;
    final count = stages.length;
    List<SwapStepStatus> upTo(int index, SwapStepStatus at) => [
      for (var i = 0; i < count; i++)
        i < index
            ? SwapStepStatus.done
            : i == index
            ? at
            : SwapStepStatus.notStarted,
    ];

    if (outcome == null) {
      return upTo(_position(s, stages), SwapStepStatus.current);
    }
    final sendIndex = _firstOf(stages, const [SwapRouteStageKind.send]);
    switch (outcome.kind) {
      case SwapOutcomeKind.completed ||
          SwapOutcomeKind.partialBelowMinimum ||
          SwapOutcomeKind.partialOtherToken:
        return List.filled(count, SwapStepStatus.done);
      case SwapOutcomeKind.cancelled || SwapOutcomeKind.noMatch:
        final approvals = s.evidence.approvalTxHashes.isNotEmpty;
        return upTo(approvals ? sendIndex : 0, SwapStepStatus.cancelled);
      case SwapOutcomeKind.refunded:
        return upTo(
          (sendIndex + 1).clamp(0, count - 1),
          SwapStepStatus.refunded,
        );
      case SwapOutcomeKind.failed:
        final reason = outcome.failure?.reason;
        final int at;
        if (reason == SwapFailureReason.approvalFailed) {
          at = _firstOf(stages, const [
            SwapRouteStageKind.approve,
            SwapRouteStageKind.resetApproval,
          ]);
        } else if (s.fundsMovement == SwapFundsMovement.sent) {
          at = (sendIndex + 1).clamp(0, count - 1);
        } else if (s.fundsMovement == SwapFundsMovement.none) {
          at = s.evidence.approvalTxHashes.isNotEmpty ? sendIndex : 0;
        } else {
          at = sendIndex;
        }
        return upTo(at, SwapStepStatus.error);
    }
  }

  static SwapTimelineStep _step(
    SwapRouteStage stage,
    SwapStepStatus status, {
    required SwapNetworks networks,
    required SwapExecutionSnapshot snapshot,
    SwapExplorerTx? explorer,
    bool routeStep = false,
  }) {
    final received = status == SwapStepStatus.done;
    return SwapTimelineStep(
      title: stageTitle(
        stage,
        networks: networks,
        received: received,
        snapshot: snapshot,
      ),
      detail: _detail(stage, networks: networks, snapshot: snapshot),
      status: status,
      link: _link(stage, snapshot, explorer, routeStep: routeStep),
    );
  }

  /// The proof a step links to, once it exists, on the networks the evidence
  /// sheet uses. A reset's hash comes first, as [_position] reads it. The
  /// route's page goes on its first leg only, and not while the route waits
  /// on the user: the page already offers it below the timeline then.
  static SwapTimelineLink? _link(
    SwapRouteStage stage,
    SwapExecutionSnapshot s,
    SwapExplorerTx? explorer, {
    required bool routeStep,
  }) {
    SwapTimelineLink? transaction(AssetId? asset, String? hash) {
      final url = hash == null ? null : explorer?.call(asset, hash);
      return url == null ? null : SwapTimelineLink.transaction(url);
    }

    final evidence = s.evidence;
    final approvals = evidence.approvalTxHashes;
    final resets = s.approval?.resetsFirst ?? false;
    final route = Uri.tryParse(evidence.providerExplorerUrl ?? '');
    return switch (stage.kind) {
      SwapRouteStageKind.resetApproval when resets => transaction(
        s.from,
        approvals.firstOrNull,
      ),
      SwapRouteStageKind.approve => transaction(
        s.from,
        approvals.length > (resets ? 1 : 0) ? approvals.last : null,
      ),
      SwapRouteStageKind.send => transaction(s.from, evidence.sourceTxHash),
      SwapRouteStageKind.bridge || SwapRouteStageKind.convert
          when routeStep &&
              route != null &&
              route.isScheme('https') &&
              s.stage != SwapProgressStage.actionRequired =>
        SwapTimelineLink.route(route),
      SwapRouteStageKind.receive => transaction(
        s.outcome?.receivedAsset ?? s.to,
        evidence.destinationTxHash,
      ),
      _ => null,
    };
  }

  /// A stage without an asset names its side of [s] as the swap's copy does:
  /// by the recorded ticker when the wallet does not know the asset.
  static String _ticker(SwapRouteStage stage, SwapExecutionSnapshot? s) {
    final receiving = stage.kind == SwapRouteStageKind.receive;
    final asset = stage.asset ?? (receiving ? s?.to : s?.from);
    if (asset != null) return SwapFormat.ticker(asset);
    return (receiving ? s?.toTicker : s?.fromTicker) ?? '';
  }

  static String _network(
    SwapRouteStage stage,
    SwapNetworks networks,
    SwapExecutionSnapshot? s,
  ) {
    final network = stage.network;
    if (network != null && network.isNotEmpty) return network;
    final sending = stage.kind == SwapRouteStageKind.send;
    final asset = stage.asset ?? (sending ? s?.from : s?.to);
    if (asset != null) return networks.networkOf(asset);
    return (sending ? s?.fromTicker : s?.toTicker) ?? '';
  }

  /// A stage's title, naming from [snapshot] what the stage does not.
  static String stageTitle(
    SwapRouteStage stage, {
    required SwapNetworks networks,
    required bool received,
    SwapExecutionSnapshot? snapshot,
  }) {
    final ticker = _ticker(stage, snapshot);
    return switch (stage.kind) {
      SwapRouteStageKind.prepare => LocaleKeys.swapStagePrepare.tr(),
      SwapRouteStageKind.resetApproval => LocaleKeys.swapStageReset.tr(),
      SwapRouteStageKind.approve => LocaleKeys.swapStageApprove.tr(
        args: [ticker],
      ),
      SwapRouteStageKind.send => LocaleKeys.swapStageSend.tr(
        args: [_network(stage, networks, snapshot)],
      ),
      SwapRouteStageKind.bridge => LocaleKeys.swapStageBridge.tr(
        args: [_network(stage, networks, snapshot)],
      ),
      SwapRouteStageKind.convert => LocaleKeys.swapStageConvert.tr(),
      SwapRouteStageKind.exchange => LocaleKeys.swapStageExchange.tr(),
      SwapRouteStageKind.receive =>
        received
            ? LocaleKeys.swapStageReceive.tr()
            : LocaleKeys.swapStageReceivePending.tr(args: [ticker]),
    };
  }

  static String _detail(
    SwapRouteStage stage, {
    required SwapNetworks networks,
    required SwapExecutionSnapshot snapshot,
  }) {
    final ticker = _ticker(stage, snapshot);
    final network = _network(stage, networks, snapshot);
    switch (stage.kind) {
      case SwapRouteStageKind.prepare:
        return LocaleKeys.swapStagePrepareDetail.tr();
      case SwapRouteStageKind.resetApproval:
        return LocaleKeys.swapStageResetDetail.tr(args: [ticker]);
      case SwapRouteStageKind.approve:
        return LocaleKeys.swapStageApproveDetail.tr();
      case SwapRouteStageKind.send:
        return LocaleKeys.swapStageSendDetail.tr();
      case SwapRouteStageKind.bridge:
        return LocaleKeys.swapStageBridgeDetail.tr();
      case SwapRouteStageKind.convert:
        return LocaleKeys.swapStageConvertDetail.tr(args: [network]);
      case SwapRouteStageKind.exchange:
        return LocaleKeys.swapStageExchangeDetail.tr();
      case SwapRouteStageKind.receive:
        final outcome = snapshot.outcome;
        final amount =
            outcome?.receivedAmount ??
            snapshot.expectedReceive ??
            snapshot.minimumReceive;
        final receivedTicker = outcome?.receivedAsset != null
            ? SwapFormat.ticker(outcome!.receivedAsset!)
            : outcome?.receivedSymbol ?? ticker;
        final what = amount == null
            ? receivedTicker
            : SwapFormat.tokens(
                amount,
                receivedTicker,
                rounding: SwapRounding.down,
              );
        final address = snapshot.toAddress;
        return address == null
            ? LocaleKeys.swapStageReceiveDetail.tr(args: [what, network])
            : LocaleKeys.swapStageReceiveDetailAddress.tr(
                args: [what, SwapFormat.short(address), network],
              );
    }
  }
}
