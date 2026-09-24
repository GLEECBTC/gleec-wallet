import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';

export 'package:web_dex/views/swap/common/swap_failure_copy.dart';
export 'package:web_dex/views/swap/common/swap_timeline.dart';

part 'swap_copy_outcomes.dart';
part 'swap_copy_recovery.dart';

/// A heading, a line of copy, an icon and a tone.
class SwapHeroCopy {
  const SwapHeroCopy({
    required this.title,
    required this.icon,
    this.body,
    this.tone = SwapTone.brand,
  });

  final String title;
  final String? body;
  final IconData icon;
  final SwapTone tone;
}

/// What a finished swap's screen may offer.
enum SwapOutcomeAction {
  /// Start a fresh swap selling what arrived instead.
  followUp,

  /// Keep what arrived and move on.
  keepToken,

  /// Consent to the re-priced quote shown old against new.
  acceptFreshQuote,

  /// Try the same swap again from a fresh quote.
  tryAgain,

  /// Open the peer-to-peer swap in the full trading interface.
  openAdvanced,

  /// Look at the transaction on an explorer.
  viewOnExplorer,

  /// Share the evidence with support.
  contactSupport,

  /// Begin a new swap.
  startAnother,
}

/// The words for a swap, running or finished, in the prototype's voice.
///
/// Built from typed state only: nothing here parses engine strings, and
/// nothing names the infrastructure behind a route.
class SwapExecutionCopy {
  SwapExecutionCopy(this.snapshot, this.networks);

  final SwapExecutionSnapshot snapshot;
  final SwapNetworks networks;

  String get fromTicker => snapshot.from == null
      ? snapshot.fromTicker
      : SwapFormat.ticker(snapshot.from!);

  String get toTicker =>
      snapshot.to == null ? snapshot.toTicker : SwapFormat.ticker(snapshot.to!);

  /// The network a stage of [kinds] names, when the route says.
  String? _stageNetwork(List<SwapRouteStageKind> kinds) {
    for (final stage in snapshot.stages.reversed) {
      final network = stage.network;
      if (kinds.contains(stage.kind) && network != null && network.isNotEmpty) {
        return network;
      }
    }
    return null;
  }

  /// Where the swap starts: the route's own naming first, since a token's
  /// config can name its network less precisely than the route does.
  String get fromNetwork =>
      _stageNetwork(const [SwapRouteStageKind.send]) ??
      (snapshot.from == null
          ? snapshot.fromTicker
          : networks.networkOf(snapshot.from!));

  /// Where the swap lands.
  String get toNetwork =>
      _stageNetwork(const [
        SwapRouteStageKind.receive,
        SwapRouteStageKind.bridge,
      ]) ??
      (snapshot.to == null
          ? snapshot.toTicker
          : networks.networkOf(snapshot.to!));

  String get _sellAmount {
    final amount = snapshot.sellAmount;
    return amount == null ? fromTicker : SwapFormat.tokens(amount, fromTicker);
  }

  String get _approvalAmount {
    final approval = snapshot.approval;
    if (approval == null) return _sellAmount;
    return SwapFormat.tokens(
      approval.exactAmount,
      SwapFormat.ticker(approval.asset),
    );
  }

  /// "0.42 ETH → 1,318.42 USDT", or the tickers when amounts are unknown.
  String get pairLine {
    final sell = snapshot.sellAmount;
    final receive =
        snapshot.outcome?.receivedAmount ??
        snapshot.expectedReceive ??
        snapshot.minimumReceive;
    final left = sell == null
        ? fromTicker
        : SwapFormat.tokens(sell, fromTicker);
    final right = receive == null
        ? toTicker
        : SwapFormat.tokens(receive, toTicker, rounding: SwapRounding.down);
    return LocaleKeys.swapActivityPair.tr(args: [left, right]);
  }

  /// What the received token is called.
  String get receivedTicker {
    final outcome = snapshot.outcome;
    final asset = outcome?.receivedAsset;
    if (asset != null) return SwapFormat.ticker(asset);
    return outcome?.receivedSymbol ?? toTicker;
  }

  String get _received {
    final amount = snapshot.outcome?.receivedAmount;
    return amount == null
        ? receivedTicker
        : SwapFormat.tokens(
            amount,
            receivedTicker,
            rounding: SwapRounding.down,
          );
  }

  /// The status hero while running; the outcome once finished.
  SwapHeroCopy get hero {
    final outcome = snapshot.outcome;
    if (outcome != null) return _outcomeHero(outcome);
    if (snapshot.delayedSince != null) {
      return SwapHeroCopy(
        title: LocaleKeys.swapProgressDelayedTitle.tr(),
        body: LocaleKeys.swapProgressDelayedBody.tr(),
        icon: Icons.hourglass_bottom_rounded,
        tone: SwapTone.warning,
      );
    }
    return _stageHero(snapshot.stage ?? SwapProgressStage.unknown);
  }

  SwapHeroCopy _stageHero(SwapProgressStage stage) {
    switch (stage) {
      case SwapProgressStage.preparing:
        return SwapHeroCopy(
          title: LocaleKeys.swapProgressPreparingTitle.tr(),
          body: LocaleKeys.swapProgressPreparingBody.tr(),
          icon: Icons.autorenew_rounded,
        );
      case SwapProgressStage.matching:
        return SwapHeroCopy(
          title: LocaleKeys.swapProgressMatchingTitle.tr(),
          body: LocaleKeys.swapProgressMatchingBody.tr(),
          icon: Icons.people_alt_outlined,
        );
      case SwapProgressStage.approving:
        final approval = snapshot.approval;
        final resetting =
            (approval?.resetsFirst ?? false) &&
            snapshot.evidence.approvalTxHashes.isEmpty;
        final ticker = approval == null
            ? fromTicker
            : SwapFormat.ticker(approval.asset);
        return resetting
            ? SwapHeroCopy(
                title: LocaleKeys.swapProgressResettingTitle.tr(),
                body: LocaleKeys.swapProgressResettingBody.tr(
                  args: [ticker, _approvalAmount],
                ),
                icon: Icons.layers_clear_outlined,
              )
            : SwapHeroCopy(
                title: LocaleKeys.swapProgressApprovingTitle.tr(),
                body: LocaleKeys.swapProgressApprovingBody.tr(
                  args: [_approvalAmount, ticker],
                ),
                icon: Icons.verified_user_outlined,
              );
      case SwapProgressStage.signing:
        return SwapHeroCopy(
          title: LocaleKeys.swapProgressSigningTitle.tr(),
          body: LocaleKeys.swapProgressSigningBody.tr(),
          icon: Icons.draw_outlined,
        );
      case SwapProgressStage.sending:
        return SwapHeroCopy(
          title: LocaleKeys.swapProgressSendingTitle.tr(args: [fromNetwork]),
          body: LocaleKeys.swapProgressSendingBody.tr(args: [fromNetwork]),
          icon: Icons.cell_tower_rounded,
        );
      case SwapProgressStage.confirming:
        return SwapHeroCopy(
          title: LocaleKeys.swapProgressConfirmingTitle.tr(args: [fromNetwork]),
          body: LocaleKeys.swapProgressConfirmingBody.tr(),
          icon: Icons.timer_outlined,
        );
      case SwapProgressStage.bridging:
        return SwapHeroCopy(
          title: LocaleKeys.swapProgressBridgingTitle.tr(args: [toNetwork]),
          body: LocaleKeys.swapProgressBridgingBody.tr(),
          icon: Icons.route_outlined,
        );
      case SwapProgressStage.awaitingDelivery:
        return SwapHeroCopy(
          title: LocaleKeys.swapProgressDeliveryTitle.tr(args: [toNetwork]),
          body: LocaleKeys.swapProgressDeliveryBody.tr(args: [toNetwork]),
          icon: Icons.place_outlined,
        );
      case SwapProgressStage.refunding:
        return SwapHeroCopy(
          title: LocaleKeys.swapProgressRefundingTitle.tr(),
          body: LocaleKeys.swapProgressRefundingBody.tr(),
          icon: Icons.undo_rounded,
          tone: SwapTone.warning,
        );
      case SwapProgressStage.actionRequired:
        return SwapHeroCopy(
          title: LocaleKeys.swapProgressActionTitle.tr(),
          body: LocaleKeys.swapProgressActionBody.tr(),
          icon: Icons.back_hand_outlined,
          tone: SwapTone.warning,
        );
      case SwapProgressStage.exchanging:
        return SwapHeroCopy(
          title: LocaleKeys.swapProgressExchangingTitle.tr(),
          body: LocaleKeys.swapProgressExchangingBody.tr(),
          icon: Icons.swap_horiz_rounded,
        );
      case SwapProgressStage.unknown:
        return SwapHeroCopy(
          title: LocaleKeys.swapProgressUnknownTitle.tr(),
          body: LocaleKeys.swapProgressUnknownBody.tr(),
          icon: Icons.radar_rounded,
        );
    }
  }
}
