import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_lock_policy.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_password_dialog.dart';

/// Why [readWalletTransferSecretResult] returned no secret.
enum WalletSecretUnread {
  /// The wallet has no seed of its own here (hardware, extensions).
  unsupported,

  /// The user closed the authorization.
  canceled,

  /// The session changed, locked or was left before the seed arrived.
  interrupted,

  /// The engine returned no usable seed.
  failed,
}

/// [readWalletTransferSecretResult], or a stand-in for it in tests.
typedef WalletSecretReader = Future<WalletSecretRead> Function(
  BuildContext context,
);

sealed class WalletSecretRead {
  const WalletSecretRead();
}

final class WalletSecretReady extends WalletSecretRead {
  const WalletSecretReady(this.secret);

  final WalletTransferSecret secret;

  @override
  String toString() => 'WalletSecretReady(<redacted>)';
}

final class WalletSecretNotRead extends WalletSecretRead {
  const WalletSecretNotRead(this.reason);

  final WalletSecretUnread reason;

  @override
  String toString() => 'WalletSecretNotRead(${reason.name})';
}

/// The open wallet's seed for a move or a backup, or null when the user
/// cancels or the session went stale.
Future<WalletTransferSecret?> readWalletTransferSecret(
  BuildContext context,
) async => switch (await readWalletTransferSecretResult(context)) {
  WalletSecretReady(:final secret) => secret,
  WalletSecretNotRead() => null,
};

/// Reads the seed under exactly the checks that reveal the recovery phrase in
/// Security settings (`SecuritySettingsPage.onViewSeedPressed`), so this is
/// no easier a way to the seed than that screen.
Future<WalletSecretRead> readWalletTransferSecretResult(
  BuildContext context,
) async {
  const interrupted = WalletSecretNotRead(WalletSecretUnread.interrupted);
  final kdfSdk = RepositoryProvider.of<KomodoDefiSdk>(context);
  final authBloc = context.read<AuthBloc>();
  final access = context.read<WalletAccessService?>();
  final AuthSessionContext session;
  try {
    session = await kdfSdk.auth.captureSessionContext();
  } on AuthSessionChangedException {
    return interrupted;
  }
  if (!context.mounted) return interrupted;
  final wallet = _walletOf(authBloc, session);
  if (wallet == null) return interrupted;
  // Checked before asking for the password, which would be asked for nothing.
  final type = TransferWalletType.fromWalletType(wallet.config.type);
  if (type == null) {
    return const WalletSecretNotRead(WalletSecretUnread.unsupported);
  }

  final String? pass = await walletPasswordDialog(context);
  if (!context.mounted) return interrupted;
  if (pass == null) {
    return const WalletSecretNotRead(WalletSecretUnread.canceled);
  }
  if (!kdfSdk.auth.isSessionContextCurrent(session)) return interrupted;
  // Started after the dialog, like the page's reveal revision.
  final revocation = _SecretReadRevocation(access?.unlockCoordinator)..start();
  try {
    final ensureAccess =
        access?.captureSensitiveOperation(session.walletId) ??
        WalletOperationGate.instance.capture().ensureCurrent;
    void ensureCurrent() {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (!context.mounted ||
          revocation.revoked ||
          !kdfSdk.auth.isSessionContextCurrent(session) ||
          (lifecycle != null && lifecycleLeavesApp(lifecycle))) {
        throw const WalletAccessException(WalletAccessFailure.staleOperation);
      }
      ensureAccess();
    }

    final seed = await RpcDispatchGuard.run(ensureCurrent, () async {
      ensureCurrent();
      final mnemonic = await kdfSdk.auth.getMnemonicPlainText(pass);
      ensureCurrent();
      return mnemonic.plaintextMnemonic;
    }, methods: const {'get_mnemonic'});
    if (_walletOf(authBloc, session) == null) return interrupted;
    if (seed == null || seed.isEmpty) {
      return const WalletSecretNotRead(WalletSecretUnread.failed);
    }
    try {
      return WalletSecretReady(
        WalletTransferSecret(
          walletName: wallet.name,
          type: type,
          seed: seed,
          phraseConfirmed: wallet.config.hasRecoveryPhrase,
        ),
      );
    } on FormatException {
      // A legacy seed too long for one code: it moves by its phrase.
      return const WalletSecretNotRead(WalletSecretUnread.unsupported);
    }
  } on WalletAccessException {
    return interrupted;
  } on WalletOperationDenied {
    return interrupted;
  } on RpcDispatchRejected {
    return interrupted;
  } on AuthSessionChangedException {
    return interrupted;
  } on Exception {
    // Never surfaced: an engine error may echo what it was given.
    return const WalletSecretNotRead(WalletSecretUnread.failed);
  } finally {
    revocation.stop();
  }
}

/// The signed-in wallet, only while it is the session's wallet.
Wallet? _walletOf(AuthBloc authBloc, AuthSessionContext session) {
  final user = authBloc.state.currentUser;
  return user != null && user.walletId == session.walletId ? user.wallet : null;
}

/// Ends a read the way the Security page revokes a reveal: leaving the app,
/// or a lock while it is in front.
final class _SecretReadRevocation with WidgetsBindingObserver {
  _SecretReadRevocation(this._coordinator);

  final WalletUnlockCoordinator? _coordinator;
  StreamSubscription<void>? _views;
  bool revoked = false;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    final coordinator = _coordinator;
    _views = coordinator?.sensitiveViewsMustClose.listen((_) {
      // Focus loss alone is the lifecycle's to answer; here only a lock
      // counts.
      if (WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.inactive &&
          !coordinator.state.isLocked) {
        return;
      }
      revoked = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      revoked = true;
    }
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_views?.cancel());
  }
}
