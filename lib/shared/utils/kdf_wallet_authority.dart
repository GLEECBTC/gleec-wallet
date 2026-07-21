import 'dart:async';

import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// The cached auth user and KDF's fresh active-wallet projection disagreed.
final class KdfWalletAuthorityUnavailable implements Exception {
  const KdfWalletAuthorityUnavailable();
}

/// Reads KDF's active wallet directly and binds it to the auth session cache.
///
/// `auth.currentUser` is intentionally cached by the SDK and can lag an
/// externally changed KDF wallet. Trading mutations must use this fresh check
/// immediately before their RPC boundary rather than trusting that cache alone.
Future<KdfUser?> freshKdfCurrentUser(
  KomodoDefiSdk sdk, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    return await _freshKdfCurrentUser(sdk).timeout(timeout);
  } on KdfWalletAuthorityUnavailable {
    rethrow;
  } catch (_) {
    // Timeouts, transport failures, malformed replies, and auth-cache read
    // failures all mean the caller lacks fresh authority for a wallet RPC.
    throw const KdfWalletAuthorityUnavailable();
  }
}

Future<KdfUser?> _freshKdfCurrentUser(KomodoDefiSdk sdk) async {
  final before = await sdk.auth.currentUser;
  final activeWallet =
      (await sdk.client.rpc.wallet.getWalletNames()).activatedWallet;
  final after = await sdk.auth.currentUser;

  if (before == null || after == null) {
    if (before == null && after == null && activeWallet == null) return null;
    throw const KdfWalletAuthorityUnavailable();
  }
  if (before.walletId != after.walletId ||
      activeWallet != after.walletId.name) {
    throw const KdfWalletAuthorityUnavailable();
  }
  return after;
}

Future<String?> freshKdfCurrentWalletId(KomodoDefiSdk sdk) async =>
    (await freshKdfCurrentUser(sdk))?.walletId.compoundId;
