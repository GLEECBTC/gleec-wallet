import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/shared/swap/swap_execution_presentation.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_links.dart';

/// The same evidenced status on the full screen, Activity and wallet row.
class SwapExecutionDisplay extends SwapExecutionCopy {
  SwapExecutionDisplay(super.snapshot, super.networks);

  SwapExecutionPresentation get presentation =>
      SwapExecutionPresentation(snapshot);

  /// The route's own page, when the route gave one a swap screen may open.
  Uri? get routePage => swapRoutePage(snapshot.evidence.providerExplorerUrl);

  /// Whether the swap waits on the user with no page to act on: the status
  /// alone would send them nowhere.
  bool get actionNeedsSupport =>
      !snapshot.isTerminal &&
      snapshot.stage == SwapProgressStage.actionRequired &&
      routePage == null;

  @override
  SwapHeroCopy get hero {
    if (presentation.awaitingBroadcastEvidence) {
      return SwapHeroCopy(
        title: 'swapCheckingTransferTitle'.tr(),
        body: 'swapCheckingTransferBody'.tr(),
        icon: Icons.schedule_rounded,
      );
    }
    final hero = super.hero;
    final body = _ownBody ?? hero.body;
    return SwapHeroCopy(
      title: hero.title,
      // At large text a receipt's address would otherwise wrap mid-address.
      body: body == null ? null : swapUnbroken(body),
      icon: hero.icon,
      tone: hero.tone,
    );
  }

  /// The line under a headline that would otherwise repeat it, or point at
  /// a page that is not there.
  String? get _ownBody {
    if (snapshot.isTerminal || snapshot.delayedSince != null) return null;
    return switch (snapshot.stage) {
      SwapProgressStage.awaitingDelivery => _deliveryBody,
      SwapProgressStage.actionRequired when routePage == null =>
        'swapProgressActionNoPageBody'.tr(),
      _ => null,
    };
  }

  /// What was sent and what is awaited. How long it usually takes is the
  /// line under the status (`SwapTimeContext`) when the swap has a start and
  /// an estimate to say it from; said here otherwise.
  String get _deliveryBody {
    final awaited = 'swapProgressDeliveryDetail'.tr(
      args: [fromTicker, toTicker],
    );
    final estimate = snapshot.estimatedDuration;
    final timed =
        snapshot.createdAt != null &&
        estimate != null &&
        estimate > Duration.zero;
    return timed ? awaited : '$awaited ${'swapProgressFewMinutes'.tr()}';
  }
}
