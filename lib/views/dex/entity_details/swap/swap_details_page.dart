import 'dart:math';

import 'package:app_theme/app_theme.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/shared/utils/swap_export.dart';
import 'package:web_dex/views/dex/entity_details/swap/swap_details.dart';
import 'package:web_dex/views/dex/entity_details/trading_details_header.dart';
import 'package:web_dex/views/dex/entity_details/trading_progress_status.dart';

class SwapDetailsPage extends StatefulWidget {
  const SwapDetailsPage(this.swapStatus, {Key? key}) : super(key: key);

  final Swap swapStatus;

  @override
  State<SwapDetailsPage> createState() => _SwapDetailsPageState();
}

class _SwapDetailsPageState extends State<SwapDetailsPage> {
  bool _isExporting = false;

  Future<void> _exportSwapData() async {
    setState(() => _isExporting = true);
    try {
      await exportSwapData(context, widget.swapStatus.uuid);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TradingDetailsHeader(title: _headerText),
        SwapProgressStatus(progress: _progress, isFailed: _isFailed),
        SwapDetails(
          swapStatus: widget.swapStatus,
          isFailed: _isFailed,
          belowUuid: UiBorderButton(
            width: 160,
            height: 32,
            borderWidth: 0,
            borderColor: theme.custom.subCardBackgroundColor,
            backgroundColor: theme.custom.subCardBackgroundColor,
            fontWeight: FontWeight.w500,
            fontSize: 11,
            text: LocaleKeys.exportSwapData.tr(),
            icon: _isExporting
                ? const UiSpinner()
                : Icon(
                    Icons.file_download,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                    size: 18,
                  ),
            onPressed: _isExporting ? null : _exportSwapData,
          ),
        ),
      ],
    );
  }

  String get _headerText {
    if (_isFailed) return LocaleKeys.tradingDetailsTitleFailed.tr();
    final haveEvents = widget.swapStatus.events.isNotEmpty;
    if (haveEvents) {
      final isSuccess =
          widget.swapStatus.events.last.event.type ==
          widget.swapStatus.successEvents.last;
      if (isSuccess) return LocaleKeys.tradingDetailsTitleCompleted.tr();
      return LocaleKeys.tradingDetailsTitleInProgress.tr();
    }
    return LocaleKeys.tradingDetailsTitleOrderMatching.tr();
  }

  bool get _isFailed {
    return widget.swapStatus.events.firstWhereOrNull(
          (event) => widget.swapStatus.errorEvents.contains(event.event.type),
        ) !=
        null;
  }

  int get _progress {
    return min(
      100,
      (100 *
              widget.swapStatus.events.length /
              (widget.swapStatus.successEvents.length - 1))
          .ceil(),
    );
  }
}
