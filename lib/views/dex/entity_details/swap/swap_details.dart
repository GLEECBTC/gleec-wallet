import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/views/dex/entity_details/swap/swap_details_step_list.dart';
import 'package:web_dex/views/dex/entity_details/swap/swap_recover_button.dart';
import 'package:web_dex/views/dex/entity_details/trading_details_coin_pair.dart';
import 'package:web_dex/views/dex/entity_details/trading_details_total_time.dart';

/// SwapDetails shows the basic information of a DEX swap including coin pairs,
/// timing and progress steps.
class SwapDetails extends StatelessWidget {
  const SwapDetails({
    super.key,
    required this.swapStatus,
    required this.isFailed,
    this.belowUuid,
  });

  final Swap swapStatus;
  final bool isFailed;
  final Widget? belowUuid;

  @override
  Widget build(BuildContext context) {
    final geometry = GleecGeometry.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: EdgeInsets.symmetric(horizontal: geometry.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (swapStatus.recoverable)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: SwapRecoverButton(uuid: swapStatus.uuid),
            ),
          // Coin pair and amounts
          TradingDetailsCoinPair(
            baseCoin: swapStatus.isTaker
                ? swapStatus.takerCoin
                : swapStatus.makerCoin,
            baseAmount: swapStatus.isTaker
                ? swapStatus.takerAmount
                : swapStatus.makerAmount,
            relCoin: swapStatus.isTaker
                ? swapStatus.makerCoin
                : swapStatus.takerCoin,
            relAmount: swapStatus.isTaker
                ? swapStatus.makerAmount
                : swapStatus.takerAmount,
            swapId: swapStatus.uuid,
            belowUuid: belowUuid,
          ),
          const SizedBox(height: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (swapStatus.myInfo != null)
                TradingDetailsTotalTime(
                  startedTime: swapStatus.myInfo!.startedAt * 1000,
                  finishedTime: _finishedTime,
                ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: SwapDetailsStepList(swapStatus: swapStatus),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int? get _finishedTime {
    if (swapStatus.events.isEmpty) {
      return null;
    }
    if ((swapStatus.successEvents.isNotEmpty &&
            swapStatus.events.last.event.type ==
                swapStatus.successEvents.last) ||
        isFailed) {
      return swapStatus.events.last.timestamp;
    }
    return null;
  }
}
