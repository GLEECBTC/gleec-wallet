import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

/// Synthetic isolated surface. A future PSE iframe/native view replaces only
/// this adapter; PAN/CVC/PIN values never enter card domain state.
class SyntheticSecureElementGateway implements CardSecureElementGateway {
  const SyntheticSecureElementGateway();

  @override
  Future<void> provisionInitialPin(
    BuildContext context, {
    required CardProvisioningHandle handle,
  }) async {
    if (handle.value.isEmpty) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidInput,
        message: 'Secure PIN setup is unavailable.',
        recovery: GnosisCardRecovery.retry,
      );
    }

    final completed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => ScreenshotSensitive(
        child: AlertDialog(
          icon: const Icon(Icons.open_in_new),
          title: Text(LocaleKeys.gnosisCard_pin_title.tr()),
          content: Semantics(
            container: true,
            liveRegion: true,
            child: Text(LocaleKeys.gnosisCard_pin_body.tr()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(LocaleKeys.gnosisCard_cancel.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(LocaleKeys.gnosisCard_pin_returned.tr()),
            ),
          ],
        ),
      ),
    );

    if (completed != true) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.unavailable,
        message: 'PIN setup was cancelled.',
        recovery: GnosisCardRecovery.retry,
      );
    }
  }

  @override
  Future<void> showCardDetails(
    BuildContext context, {
    required String cardId,
  }) => _showSecureHandoff(
    context,
    title: LocaleKeys.details.tr(),
    body: LocaleKeys.gnosisCard_externalNotice.tr(),
  );

  @override
  Future<void> showPin(BuildContext context, {required String cardId}) =>
      _showSecureHandoff(
        context,
        title: LocaleKeys.gnosisCard_pin_title.tr(),
        body: LocaleKeys.gnosisCard_pin_body.tr(),
      );

  Future<void> _showSecureHandoff(
    BuildContext context, {
    required String title,
    required String body,
  }) => showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => ScreenshotSensitive(
      child: AlertDialog(
        icon: const Icon(Icons.open_in_new),
        title: Text(title),
        content: Semantics(
          container: true,
          liveRegion: true,
          child: Text(body),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(LocaleKeys.close.tr()),
          ),
        ],
      ),
    ),
  );
}
