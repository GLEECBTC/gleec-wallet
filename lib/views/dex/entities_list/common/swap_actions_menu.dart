import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/shared/utils/swap_export.dart';
import 'package:web_dex/shared/utils/utils.dart';

enum SwapAction { copyUuid, exportData }

class SwapActionsMenu extends StatefulWidget {
  const SwapActionsMenu({super.key, required this.swap});

  final Swap swap;

  @override
  State<SwapActionsMenu> createState() => _SwapActionsMenuState();
}

class _SwapActionsMenuState extends State<SwapActionsMenu> {
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SwapAction>(
      icon: _isExporting
          ? const UiSpinner(width: 16, height: 16, strokeWidth: 2)
          : const Icon(Icons.more_vert, size: 18),
      onSelected: (action) async {
        switch (action) {
          case SwapAction.copyUuid:
            copyToClipBoard(
              context,
              widget.swap.uuid,
              LocaleKeys.copiedUuidToClipboard.tr(),
            );
          case SwapAction.exportData:
            if (_isExporting) return;
            setState(() => _isExporting = true);
            try {
              await exportSwapData(context, widget.swap.uuid);
            } finally {
              if (mounted) setState(() => _isExporting = false);
            }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: SwapAction.copyUuid,
          child: Text(LocaleKeys.copyUuid.tr()),
        ),
        PopupMenuItem(
          value: SwapAction.exportData,
          child: Text(LocaleKeys.exportSwapData.tr()),
        ),
      ],
    );
  }
}
