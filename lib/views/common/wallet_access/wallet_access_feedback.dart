import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';

/// Explains why a wallet-access step did not finish.
///
/// [passwordEntered] is whether the user typed their current wallet password
/// for this attempt: only then can a password have been wrong. [unlocking]
/// separates opening the wallet from confirming a change to it, where a
/// cancellation means nothing was changed.
String walletAccessFailureText(
  Object error, {
  required bool passwordEntered,
  bool unlocking = true,
}) {
  final key = switch (error) {
    WalletAccessException(:final failure) => switch (failure) {
      WalletAccessFailure.canceled =>
        unlocking ? 'authUnlockCanceled' : 'authConfirmationCanceled',
      WalletAccessFailure.incorrectPassword => LocaleKeys.passwordNotAccepted,
      WalletAccessFailure.busy => 'authProtectionBusy',
      WalletAccessFailure.staleOperation => 'authProtectionStale',
      WalletAccessFailure.lockedOut when !passwordEntered =>
        'authDeviceUnlockLockedOut',
      WalletAccessFailure.invalidated || WalletAccessFailure.missingCredential
          when !passwordEntered =>
        'authDeviceUnlockReset',
      _ => passwordEntered ? 'authAccessCheckFailed' : 'authDeviceUnlockFailed',
    },
    AuthException(type: AuthExceptionType.incorrectPassword) =>
      LocaleKeys.passwordNotAccepted,
    // Nothing was sent, or the engine could not be asked: the password was
    // never judged, so the user can simply try again.
    RpcDispatchRejected() ||
    AuthSessionChangedException() => 'authProtectionStale',
    AuthException(type: AuthExceptionType.apiConnectionError) ||
    AuthIdentityUnavailableException() => 'authAccessCheckFailed',
    // The engine reports a wrong password in more than one shape.
    _ =>
      passwordEntered
          ? LocaleKeys.passwordNotAccepted
          : 'authDeviceUnlockFailed',
  };
  return key.tr();
}

/// What a [WalletAccessNotice] is telling the user.
enum WalletAccessTone { info, success, warning, error }

/// One status line: an icon that carries the tone and text at full contrast,
/// so the meaning never depends on colour alone.
class WalletAccessNotice extends StatelessWidget {
  const WalletAccessNotice({
    required this.text,
    this.tone = WalletAccessTone.info,
    this.announce = true,
    super.key,
  });

  final String text;
  final WalletAccessTone tone;

  /// Whether screen readers hear it as it appears. Off for standing notes.
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (tone) {
      WalletAccessTone.info => (Icons.info_outline, scheme.primary),
      WalletAccessTone.success => (
        Icons.check_circle_outline,
        theme.custom.successColor,
      ),
      WalletAccessTone.warning => (
        Icons.warning_amber_rounded,
        theme.custom.warningColor,
      ),
      WalletAccessTone.error => (Icons.error_outline, scheme.error),
    };
    return Semantics(
      container: true,
      liveRegion: announce,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 20, color: color)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A busy indicator that names what is happening and stays still when the
/// user asked for reduced motion.
class WalletAccessProgress extends StatelessWidget {
  const WalletAccessProgress({
    required this.label,
    this.linear = false,
    this.showLabel = false,
    super.key,
  });

  final String label;
  final bool linear;

  /// Whether [label] is also drawn beside the indicator.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    // A spinner stopped at its first frame draws nothing, so with reduced
    // motion the circular form shows a fixed arc instead.
    final still = MediaQuery.disableAnimationsOf(context);
    final scheme = Theme.of(context).colorScheme;
    final indicator = TickerMode(
      enabled: !still,
      child: linear
          // The default track is the surface colour, which vanishes on a card.
          ? LinearProgressIndicator(
              backgroundColor: scheme.primary.withValues(alpha: 0.24),
            )
          : SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: still ? 0.75 : null,
              ),
            ),
    );
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: !showLabel
            ? indicator
            : linear
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurface),
                  ),
                  const SizedBox(height: 8),
                  indicator,
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  indicator,
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
