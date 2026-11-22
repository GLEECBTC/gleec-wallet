import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';

/// Names the wallet being opened; the generic greeting when no name is known.
/// A wallet without a lock is opened rather than unlocked.
String walletUnlockTitle(String? walletName, {bool locked = true}) =>
    walletName == null || walletName.isEmpty
    ? 'authUnlockTitle'.tr()
    : (locked ? 'authUnlockWalletTitle' : 'authOpenWalletTitle').tr(
        args: [walletName],
      );

/// The primary unlock action names the method it will use, so it never reads
/// as one of two equal "Use …" choices.
String walletUnlockMethodLabel(WalletAccessStatus? status) {
  if (status == null || !status.hasManagedCredential) return 'authUnlock'.tr();
  if (status.protection == CredentialProtection.passkey) {
    return 'authUnlockWithPasskey'.tr();
  }
  return (status.requiresAuthentication
          ? 'authUnlockWithDevice'
          : 'authOpenWallet')
      .tr();
}

/// A cancelled prompt is the user's own choice, not a fault to alarm about.
WalletAccessTone walletAccessFailureTone(Object error) =>
    error is WalletAccessException &&
        error.failure == WalletAccessFailure.canceled
    ? WalletAccessTone.info
    : WalletAccessTone.error;

/// The one primary action of an unlock or authorization surface.
class WalletAccessPrimaryButton extends StatelessWidget {
  const WalletAccessPrimaryButton({
    required this.text,
    required this.onPressed,
    this.busy = false,
    this.busyText,
    this.autofocus = false,
    this.focusNode,
    this.buttonKey,
    super.key,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool busy;

  /// Shown in place of [text] while busy; "Please wait" when omitted.
  final String? busyText;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Key of the kit button itself, for callers that look it up by type.
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: busy,
    child: UiPrimaryButton(
      key: buttonKey,
      expandForText: true,
      autofocus: autofocus,
      focusNode: focusNode,
      text: busy ? busyText ?? LocaleKeys.pleaseWait.tr() : text,
      // A spinner that may not turn is only a stray dot; the label says it.
      prefix: busy && !MediaQuery.disableAnimationsOf(context)
          ? const _ButtonProgress()
          : null,
      // A disabled button drops keyboard focus and never gets it back, so a
      // busy one stays enabled and ignores presses.
      onPressed: busy && onPressed != null ? () {} : onPressed,
    ),
  );
}

class _ButtonProgress extends StatelessWidget {
  const _ButtonProgress();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 10),
    child: ExcludeSemantics(
      child: ProgressIndicatorTheme(
        // Match the label, not the primary colour the button is filled with.
        data: ProgressIndicatorThemeData(
          color: DefaultTextStyle.of(context).style.color,
        ),
        // The button's own label already says it is busy.
        child: const WalletAccessProgress(label: ''),
      ),
    ),
  );
}

/// The quiet alternative beside the primary action.
class WalletAccessSecondaryButton extends StatelessWidget {
  const WalletAccessSecondaryButton({
    required this.text,
    required this.onPressed,
    this.prefix,
    super.key,
  });

  final String text;
  final VoidCallback? onPressed;
  final Widget? prefix;

  @override
  Widget build(BuildContext context) => Semantics(
    // A node of its own: merged upwards, the button would take the title and
    // notices beside it as its name and lose its own label.
    container: true,
    // The kit's border button is an ink well, which reports a tap but not
    // that it is a button.
    button: true,
    enabled: onPressed != null,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: UiBorderButton(
        width: double.infinity,
        allowMultiline: true,
        borderWidth: 2,
        borderColor: theme.custom.specificButtonBorderColor,
        prefix: prefix,
        text: text,
        onPressed: onPressed,
      ),
    ),
  );
}

/// A way out of the surface: switch wallet, recover, cancel.
class WalletAccessTertiaryButton extends StatelessWidget {
  const WalletAccessTertiaryButton({
    required this.text,
    required this.onPressed,
    super.key,
  });

  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => UiUnderlineTextButton(
    expandForText: true,
    text: text,
    onPressed: onPressed,
  );
}

/// Explains a password prompt the user may not expect: the wallet's usual
/// unlock could not be read, or its password was created for it.
class WalletPasswordGuidance extends StatelessWidget {
  const WalletPasswordGuidance({
    required this.unlockUnavailable,
    required this.generatedPassword,
    super.key,
  });

  /// Reads a status lookup: an error means the wallet's saved unlock could not
  /// be read; otherwise the answer says whether its password was generated.
  WalletPasswordGuidance.of(
    AsyncSnapshot<WalletAccessStatus?> snapshot, {
    Key? key,
  }) : this(
         unlockUnavailable: snapshot.hasError,
         generatedPassword: snapshot.data?.generatedPassword ?? false,
         key: key,
       );

  final bool unlockUnavailable;
  final bool generatedPassword;

  /// Whether the user may be asked for a password they never chose, so the
  /// recovery phrase should be offered as the prominent alternative.
  bool get passwordMayBeUnknown => unlockUnavailable || generatedPassword;

  @override
  Widget build(BuildContext context) {
    if (!passwordMayBeUnknown) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (unlockUnavailable) ...[
            WalletAccessNotice(
              key: const Key('wallet-unlock-unavailable'),
              tone: WalletAccessTone.warning,
              text:
                  (kIsWeb
                          ? 'authPasskeyUnlockUnavailable'
                          : 'authDeviceUnlockUnavailable')
                      .tr(),
            ),
            const SizedBox(height: 8),
          ],
          WalletAccessNotice(
            key: const Key('wallet-generated-password-hint'),
            announce: false,
            text:
                (generatedPassword
                        ? 'authGeneratedPasswordHint'
                        : 'authPasswordMaybeGeneratedHint')
                    .tr(),
          ),
        ],
      ),
    );
  }
}
