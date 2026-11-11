import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/model/authorize_mode.dart';
import 'package:web_dex/services/storage/get_storage.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_wrapper.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';

/// Service to handle remember wallet functionality
class RememberWalletService {
  static final _log = Logger('RememberWalletService');
  static bool _hasShownRememberMeDialogThisSession = false;
  static bool _hasBeenLoggedInThisSession = false;
  static int _presentationGeneration = 0;
  static bool _hasExplicitSetupIntent = false;

  /// An explicit setup or browse choice takes precedence over a pending
  /// startup lookup. It does not alter durable automatic-entry preferences.
  static void cancelPendingAutomaticEntry() {
    _presentationGeneration++;
    _hasExplicitSetupIntent = true;
  }

  static bool _canPresent(BuildContext context, int generation) {
    if (!context.mounted ||
        generation != _presentationGeneration ||
        _hasExplicitSetupIntent ||
        _hasShownRememberMeDialogThisSession) {
      return false;
    }
    final auth = context.read<AuthBloc>().state;
    return auth.mode == AuthorizeMode.noLogin &&
        !auth.isSignedIn &&
        !auth.isLoading;
  }

  /// Check and possibly show the remembered wallet dialog
  static Future<void> maybeShowRememberedWallet(BuildContext context) async {
    final generation = _presentationGeneration;
    if (!_canPresent(context, generation)) return;

    final access = context.read<WalletAccessService?>();
    if (access != null) {
      if (await access.automaticEntrySuppressed) return;
      if (!context.mounted || !_canPresent(context, generation)) return;
      final wallet = await access.lastWallet();
      if (!context.mounted || !_canPresent(context, generation)) return;
      if (wallet != null) {
        _hasShownRememberMeDialogThisSession = true;
        await AppDialog.showWithCallback<void>(
          context: context,
          width: 360,
          barrierDismissible: false,
          childBuilder: (closeDialog) => WalletsManagerWrapper(
            eventType: WalletsManagerEventType.header,
            onCancel: closeDialog,
            selectedWallet: wallet,
            rememberMe: true,
            onSuccess: (_) => closeDialog(),
          ),
        );
        return;
      }
    }

    if (!context.mounted || !_canPresent(context, generation)) return;
    final storage = getStorage();
    final walletsRepo = context.read<WalletsRepository>();
    final storedWalletData = await storage.read(lastLoggedInWalletKey);
    if (!context.mounted || !_canPresent(context, generation)) return;
    if (storedWalletData == null) return;

    WalletId walletId;
    try {
      // Parse stored wallet data - handle both JSON string and Map formats
      if (storedWalletData is String) {
        // Try to parse as JSON string first (new format)
        try {
          final parsedData =
              jsonDecode(storedWalletData) as Map<String, dynamic>;
          walletId = WalletId.fromJson(parsedData);
        } catch (_) {
          // If JSON parsing fails, treat as legacy wallet name
          walletId = WalletId.fromName(
            storedWalletData,
            AuthOptions(derivationMethod: DerivationMethod.iguana),
          );
        }
      } else if (storedWalletData is Map<String, dynamic>) {
        walletId = WalletId.fromJson(storedWalletData);
      } else {
        // Unrecognized format, clear invalid data
        await storage.delete(lastLoggedInWalletKey);
        return;
      }
    } catch (e) {
      // Only clear data for actual parsing errors
      await storage.delete(lastLoggedInWalletKey);
      return;
    }

    try {
      final wallets = walletsRepo.wallets ?? await walletsRepo.getWallets();

      if (!context.mounted || !_canPresent(context, generation)) return;

      // Match by wallet name and optionally by pubkey hash for more precise matching
      final wallet = wallets.where((w) {
        if (w.name != walletId.name) return false;
        // If we have a pubkey hash in the stored WalletId, ensure it matches
        if (walletId.hasFullIdentity && w.config.pubKey != null) {
          // Verify if wallet.config.pubKey corresponds to walletId.pubkeyHash
          final configuredIdentity = w.config.pubKey!.trim().toLowerCase();
          final storedIdentity = walletId.pubkeyHash!.trim().toLowerCase();
          final legacyIdentity = md5
              .convert(utf8.encode(w.config.pubKey!))
              .toString();
          if (configuredIdentity != storedIdentity &&
              legacyIdentity != storedIdentity) {
            return false;
          }
        }
        return true;
      }).firstOrNull;

      if (wallet == null) return;

      if (!context.mounted || !_canPresent(context, generation)) return;

      // Use AppDialog - a replacement for deprecated PopupDispatcher
      // Allow AppDialog to use its default root navigator behavior to avoid navigation stack corruption
      // Mark that we've shown the dialog to prevent multiple prompts in a single session
      _hasShownRememberMeDialogThisSession = true;

      await AppDialog.showWithCallback<void>(
        context: context,
        width: 320,
        barrierDismissible: false,
        // Keep default useRootNavigator (true) to avoid navigation stack corruption
        childBuilder: (closeDialog) => WalletsManagerWrapper(
          eventType: WalletsManagerEventType.header,
          // Without this, cancelling the remembered-wallet prompt dropped the
          // user into the wallet manager instead of dismissing the dialog.
          onCancel: closeDialog,
          selectedWallet: wallet,
          rememberMe: true,
          onSuccess: (wallet) => closeDialog(),
        ),
      );
    } catch (e, stackTrace) {
      // Log the error for debugging and monitoring
      _log.severe('Failed to show remembered wallet dialog', e, stackTrace);

      // Reset the flag so future attempts can be made if this one failed
      _hasShownRememberMeDialogThisSession = false;

      // Re-throw the error to prevent silent failures that could leave the app
      // in an inconsistent state. The caller should handle this appropriately.
      rethrow;
    }
  }

  /// Track when user has been logged in
  static void trackUserLoggedIn() {
    _hasBeenLoggedInThisSession = true;
  }

  /// Reset remember me dialog state when user logs out
  static void resetOnLogout() {
    _presentationGeneration++;
    _hasExplicitSetupIntent = false;
    _hasShownRememberMeDialogThisSession = false;
    _hasBeenLoggedInThisSession = false;
  }

  /// Check if remember me dialog has been shown this session
  static bool get hasShownRememberMeDialogThisSession =>
      _hasShownRememberMeDialogThisSession;

  /// Check if user has been logged in this session
  static bool get hasBeenLoggedInThisSession => _hasBeenLoggedInThisSession;
}
