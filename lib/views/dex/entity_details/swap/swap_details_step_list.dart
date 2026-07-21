import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/views/dex/entity_details/swap/swap_details_step.dart';

class SwapDetailsStepList extends StatelessWidget {
  const SwapDetailsStepList({super.key, required this.swapStatus});
  final Swap swapStatus;

  @override
  Widget build(BuildContext context) {
    final bool isFailedSwap = _checkFailedSwap();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: swapStatus.successEvents.map((event) {
        if ((event == 'MakerPaymentSpentByWatcher' &&
                swapStatus.events.any(
                  (SwapEventItem e) => e.event.type == 'MakerPaymentSpent',
                )) ||
            (event == 'MakerPaymentSpent' &&
                swapStatus.events.any(
                  (SwapEventItem e) =>
                      e.event.type == 'MakerPaymentSpentByWatcher',
                ))) {
          return const SizedBox.shrink();
        }

        final bool isLastStep = event == 'Finished';
        final bool isExistStep =
            swapStatus.events.firstWhereOrNull((e) => e.event.type == event) !=
            null;
        final bool isProcessedStep =
            isExistStep && !(isLastStep && isFailedSwap);
        final bool isCurrentStep =
            !isProcessedStep && _checkCurrentStep(swapStatus, event);
        final bool isDisabledStep =
            !isCurrentStep && !isProcessedStep || (isLastStep && isFailedSwap);
        final SwapEventItem? eventData = swapStatus.events.firstWhereOrNull(
          (e) => e.event.type == event,
        );
        final Coin? coin = _getCoinForTransaction(context, event, swapStatus);

        return SwapDetailsStep(
          key: Key('swap-details-step-$event'),
          event: event,
          isCurrentStep: isCurrentStep,
          isProcessedStep: isProcessedStep,
          isDisabled: isDisabledStep,
          isLastStep: isLastStep,
          isFailedStep: isCurrentStep && isFailedSwap,
          timeSpent: _calculateTimeSpent(event),
          txHash: eventData?.event.data?.txHash,
          coin: coin,
        );
      }).toList(),
    );
  }

  bool _checkCurrentStep(Swap swapStatus, String event) {
    final int index = swapStatus.successEvents.indexOf(event);
    final int previousStepIndex = swapStatus.events.indexWhere(
      (e) => (swapStatus.successEvents.indexOf(e.event.type) + 1) == index,
    );
    return previousStepIndex != -1;
  }

  bool _checkFailedSwap() =>
      swapStatus.events.firstWhereOrNull(
        (e) => swapStatus.errorEvents.contains(e.event.type),
      ) !=
      null;

  bool isLastStep(String event) =>
      swapStatus.successEvents.isNotEmpty &&
      event == swapStatus.successEvents.last;

  int _calculateTimeSpent(String event) {
    final SwapEventItem? currentEvent = swapStatus.events.firstWhereOrNull(
      (e) => e.event.type == event,
    );
    if (currentEvent == null) {
      return 0;
    }
    final int currentEventIndex = swapStatus.events.indexWhere(
      (e) => e.event.type == currentEvent.event.type,
    );
    if (currentEventIndex <= 0) {
      return currentEvent.timestamp -
          (swapStatus.myInfo?.startedAt ?? 0) * 1000;
    }
    final SwapEventItem previousEvent =
        swapStatus.events[currentEventIndex - 1];
    return currentEvent.timestamp - previousEvent.timestamp;
  }

  Coin? _getCoinForTransaction(
    BuildContext context,
    String event,
    Swap swapStatus,
  ) {
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final List<String> takerEvents = [
      'TakerPaymentSent',
      'TakerPaymentSpent',
      'TakerFeeSent',
      'TakerFeeValidated',
      'TakerPaymentReceived',
    ];
    final List<String> makerEvents = [
      'MakerPaymentReceived',
      'MakerPaymentSpent',
      'MakerPaymentSpentByWatcher',
      'MakerPaymentSent',
    ];
    if (takerEvents.contains(event)) {
      return coinsRepository.getCoin(swapStatus.takerCoin);
    }
    if (makerEvents.contains(event)) {
      return coinsRepository.getCoin(swapStatus.makerCoin);
    }
    return null;
  }
}
