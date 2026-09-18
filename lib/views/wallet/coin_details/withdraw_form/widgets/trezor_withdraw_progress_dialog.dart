import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/common/hw_wallet_dialog/constants.dart';
import 'package:web_dex/shared/ui/ui_light_button.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

/// Dialog shown during Trezor withdrawal operations to inform users
/// they need to interact with their hardware device
class TrezorWithdrawProgressDialog extends StatelessWidget {
  const TrezorWithdrawProgressDialog({
    Key? key,
    required this.message,
    required this.onCancel,
  }) : super(key: key);

  final String message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 24),
            const UiSpinner(width: 58, height: 58, strokeWidth: 4),
            const SizedBox(height: 48),
            Text(
              LocaleKeys.userActionRequired.tr(),
              style: trezorDialogTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: trezorDialogDescription,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            UiLightButton(
              text: LocaleKeys.cancel.tr(),
              onPressed: () => onCancel(),
            ),
          ],
        ),
      ),
    );
  }
}
