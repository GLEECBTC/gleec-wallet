import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/analytics/events/security_events.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/bloc/security_settings/security_settings_state.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/seed_backup/seed_backup_policy.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';
import 'package:web_dex/views/common/wallet_password_dialog/mnemonic_prompt.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_back_button.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_confirm_success.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_confirmation/seed_confirmation.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_show.dart';

/// Wallets acknowledged this session, keyed by authenticated wallet identity.
///
/// Acknowledgement is intentionally **in memory and per session**. It suppresses
/// repeat nagging within one sitting while still re-prompting on the next
/// launch, which is what keeps the warning meaningful for a wallet that is
/// still not backed up. Persisting it would turn the gate into a one-time
/// notice, and writing `has_backup` instead would be worse: three other
/// surfaces (the global banner, the desktop menu indicator and the settings
/// label) read that flag as proof the user holds their words.
final Set<AuthSessionContext> _acknowledgedThisSession = <AuthSessionContext>{};

@visibleForTesting
void resetSeedBackupAcknowledgements() => _acknowledgedThisSession.clear();

/// Ensures the user has been warned before an address they could fund is
/// revealed. Returns true when the caller may proceed.
///
/// Reads the authenticated user published by the SDK through [AuthBloc].
/// Initial creation metadata is persisted before that user is published.
///
/// There is deliberately no fail-open branch for a missing [AuthBloc]. It is
/// provided above `MaterialApp.router`, so it is an ancestor of every route and
/// every dialog overlay; a `ProviderNotFoundException` here means a test
/// harness is wrong, and silently passing through would reintroduce the
/// fail-open pattern this work exists to remove.
Future<bool> ensureSeedBackedUp(
  BuildContext context, {
  required SeedBackupGateReason reason,
  bool isTestCoin = false,
}) async {
  final authBloc = context.read<AuthBloc>();
  final user = authBloc.state.currentUser;
  final wallet = user?.wallet;
  if (!seedBackupGateRequired(wallet: wallet, isTestCoin: isTestCoin)) {
    return true;
  }
  final sdk = context.read<KomodoDefiSdk>();
  final AuthSessionContext session;
  try {
    session = await sdk.auth.captureSessionContext();
  } on AuthSessionChangedException {
    return false;
  }
  if (!context.mounted || !sdk.auth.isSessionContextCurrent(session)) {
    return false;
  }
  final walletId = user!.walletId;
  if (_acknowledgedThisSession.contains(session)) return true;

  final proceed = await AppDialog.show<bool>(
    context: context,
    width: 420,
    barrierDismissible: false,
    child: _SeedBackupGateDialog(
      wallet: wallet!,
      walletId: walletId,
      session: session,
      sdk: sdk,
      reason: reason,
      // Passed in rather than read off the dialog's own context: AppDialog
      // pushes onto the root navigator, which is not guaranteed to sit under
      // the same provider scope as the caller.
      authBloc: authBloc,
    ),
  );

  return proceed == true && sdk.auth.isSessionContextCurrent(session);
}

class _SeedBackupGateDialog extends StatefulWidget {
  const _SeedBackupGateDialog({
    required this.wallet,
    required this.walletId,
    required this.session,
    required this.sdk,
    required this.reason,
    required this.authBloc,
  });

  final Wallet wallet;
  final WalletId walletId;
  final AuthSessionContext session;
  final KomodoDefiSdk sdk;
  final SeedBackupGateReason reason;
  final AuthBloc authBloc;

  @override
  State<_SeedBackupGateDialog> createState() => _SeedBackupGateDialogState();
}

class _SeedBackupGateDialogState extends State<_SeedBackupGateDialog> {
  /// Held only for the life of this dialog and dropped on the way out. Dart
  /// strings are immutable, so this matches the existing convention of
  /// releasing the reference rather than claiming zeroisation.
  String _seed = '';
  bool _backingUp = false;
  bool _closing = false;
  StreamSubscription<AuthSessionContext?>? _sessionSubscription;

  @override
  void initState() {
    super.initState();
    _sessionSubscription = widget.sdk.auth.watchSessionContext().listen((_) {
      if (!_isCurrentWallet) _close(false);
    });
  }

  bool get _isCurrentWallet =>
      widget.sdk.auth.isSessionContextCurrent(widget.session);

  @override
  void dispose() {
    _seed = '';
    _sessionSubscription?.cancel();
    super.dispose();
  }

  void _close(bool proceed) {
    if (!mounted || _closing) return;
    _closing = true;
    _seed = '';
    final route = ModalRoute.of(context);
    if (route == null) return;
    final mayProceed = proceed && _isCurrentWallet;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop(mayProceed);
    } else {
      // A password prompt may be above this route when auth changes.
      navigator.removeRoute(route, mayProceed);
    }
  }

  /// Declines the reveal *and* clears the way to actually restore.
  ///
  /// You cannot import a recovery phrase while signed into another wallet, so
  /// stopping at "declined" left the user stranded on a coin page with no
  /// address and no next step - the label promised an intent the button did
  /// not deliver. Signing out is non-destructive (the wallet stays in the
  /// list) and `MainLayout`'s auth listener routes back to the wallet page,
  /// where Connect wallet opens the entry screen with the restore row on it.
  void _restoreInstead() {
    if (!_isCurrentWallet) {
      _close(false);
      return;
    }
    _close(false);
    widget.authBloc.add(const AuthSignOutRequested());
  }

  void _continueAnyway() {
    if (!_isCurrentWallet) {
      _close(false);
      return;
    }
    // A reused display name must not inherit a different wallet's warning.
    if (widget.walletId.hasFullIdentity) {
      _acknowledgedThisSession.add(widget.session);
    }
    _close(true);
  }

  Future<void> _startBackup() async {
    if (!_isCurrentWallet) {
      _close(false);
      return;
    }
    final seed = await promptForPlaintextMnemonic(context);
    if (!mounted) return;
    if (!_isCurrentWallet) {
      _close(false);
      return;
    }
    if (seed == null) return;
    setState(() {
      _seed = seed;
      _backingUp = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthBlocState>(
      bloc: widget.authBloc,
      listener: (context, state) {
        if (!_isCurrentWallet) _close(false);
      },
      child: Builder(
        builder: (context) {
          if (!_backingUp) {
            return _SeedBackupGateNotice(
              isGenerated: seedWasGeneratedForUser(widget.wallet),
              reason: widget.reason,
              onBackUp: _startBackup,
              onImportInstead: _restoreInstead,
              onContinueAnyway: _continueAnyway,
            );
          }

          return BlocProvider<SecuritySettingsBloc>(
            create: (context) => SecuritySettingsBloc(
              SecuritySettingsState.initialState(),
              kdfSdk: RepositoryProvider.of<KomodoDefiSdk>(context),
            )..add(const ShowSeedEvent()),
            child: BlocConsumer<SecuritySettingsBloc, SecuritySettingsState>(
              listener: (context, state) {
                // `SeedShow` and `SeedConfirmation` each embed a back button that
                // dispatches ResetEvent, landing the bloc on `securityMain` - a step
                // this dialog has no widget for. Treat it as "backed out" rather than
                // patching either widget, which keeps their existing
                // `backup_skipped` analytics intact.
                if (state.step == SecuritySettingsStep.securityMain) {
                  _seed = '';
                  _close(false);
                }
              },
              builder: (context, state) {
                final Widget content;
                switch (state.step) {
                  case SecuritySettingsStep.seedShow:
                    // Empty key map on purpose: `SeedShow` renders no private-key
                    // section for it, which is how this flow avoids the settings
                    // page's per-coin `showPrivKey` round trips.
                    content = SeedShow(seedPhrase: _seed, privKeys: const {});
                    break;
                  case SecuritySettingsStep.seedConfirm:
                    content = SeedConfirmation(
                      seedPhrase: _seed,
                      session: widget.session,
                    );
                    break;
                  case SecuritySettingsStep.seedSuccess:
                    _seed = '';
                    return _SeedBackupGateSuccess(onDone: () => _close(true));
                  default:
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: UiSpinner(),
                      ),
                    );
                }

                if (!isMobile) return content;

                // The settings pages rely on their mobile page header for Back.
                // This modal needs its own escape, including for custom seeds that
                // cannot proceed to the confirmation quiz.
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SeedBackButton(() {
                        final isConfirming =
                            state.step == SecuritySettingsStep.seedConfirm;
                        context.read<AnalyticsBloc>().add(
                          AnalyticsBackupSkippedEvent(
                            stageSkipped: isConfirming
                                ? 'seed_confirm'
                                : 'seed_show',
                            hdType: widget.wallet.config.type.name,
                          ),
                        );
                        context.read<SecuritySettingsBloc>().add(
                          isConfirming
                              ? const ShowSeedEvent()
                              : const ResetEvent(),
                        );
                      }),
                    ),
                    content,
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _SeedBackupGateNotice extends StatelessWidget {
  const _SeedBackupGateNotice({
    required this.isGenerated,
    required this.reason,
    required this.onBackUp,
    required this.onImportInstead,
    required this.onContinueAnyway,
  });

  final bool isGenerated;
  final SeedBackupGateReason reason;
  final VoidCallback onBackUp;
  final VoidCallback onImportInstead;
  final VoidCallback onContinueAnyway;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('seed-backup-gate-notice'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.shield_outlined, size: 40, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          LocaleKeys.seedBackupGateTitle.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
        ),
        const SizedBox(height: 12),
        Text(
          isGenerated
              ? LocaleKeys.seedBackupGateGeneratedBody.tr()
              : LocaleKeys.seedBackupGateBody.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 24),
        UiPrimaryButton(
          key: const Key('seed-backup-gate-backup-button'),
          height: 48,
          text: LocaleKeys.seedBackupGateBackUpNow.tr(),
          onPressed: onBackUp,
        ),
        if (isGenerated) ...[
          const SizedBox(height: 12),
          UiUnderlineTextButton(
            key: const Key('seed-backup-gate-import-instead-button'),
            text: LocaleKeys.seedBackupGateImportInstead.tr(),
            onPressed: onImportInstead,
          ),
        ],
        const SizedBox(height: 4),
        UiUnderlineTextButton(
          key: const Key('seed-backup-gate-continue-button'),
          text: LocaleKeys.seedBackupGateContinueAnyway.tr(),
          onPressed: onContinueAnyway,
        ),
      ],
    );
  }
}

class _SeedBackupGateSuccess extends StatelessWidget {
  const _SeedBackupGateSuccess({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SeedConfirmSuccess(),
        const SizedBox(height: 16),
        UiPrimaryButton(
          key: const Key('seed-backup-gate-done-button'),
          height: 48,
          text: LocaleKeys.seedBackupGateShowAddress.tr(),
          onPressed: onDone,
        ),
      ],
    );
  }
}
