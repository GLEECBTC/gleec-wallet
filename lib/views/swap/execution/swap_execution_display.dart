import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/shared/swap/swap_execution_presentation.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';

/// The same evidenced status on the full screen, Activity and wallet row.
class SwapExecutionDisplay extends SwapExecutionCopy {
  SwapExecutionDisplay(super.snapshot, super.networks);

  SwapExecutionPresentation get presentation =>
      SwapExecutionPresentation(snapshot);

  @override
  SwapHeroCopy get hero => presentation.awaitingBroadcastEvidence
      ? SwapHeroCopy(
          title: 'swapCheckingTransferTitle'.tr(),
          body: 'swapCheckingTransferBody'.tr(),
          icon: Icons.schedule_rounded,
        )
      : super.hero;
}
