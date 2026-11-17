import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/utils/debug_wallet_source.dart';

Future<void> initDebugData(
  AuthBloc authBloc,
  WalletsRepository walletsRepository,
) async {
  try {
    final testWalletStr = await loadDebugWalletSource();
    if (testWalletStr == null) return;
    final Map<String, dynamic> debugDataJson = jsonDecode(testWalletStr);
    final Map<String, dynamic>? newWalletJson = debugDataJson['wallet'];
    if (newWalletJson == null) {
      return;
    }

    if (newWalletJson['automateLogin'] == true) {
      final Wallet? debugWallet = await _createDebugWallet(
        walletsRepository,
        newWalletJson,
        hasBackup: true,
      );
      if (debugWallet == null) {
        return;
      }

      authBloc.add(
        walletsRepository.wallets?.any(
                  (wallet) => wallet.name == debugWallet.name,
                ) ==
                true
            ? AuthSignInRequested(
                wallet: debugWallet,
                password: newWalletJson['password'],
              )
            : AuthRestoreRequested(
                seed: newWalletJson['seed'],
                wallet: debugWallet,
                password: newWalletJson['password'],
              ),
      );
    }
  } catch (e) {
    return;
  }
}

Future<Wallet?> _createDebugWallet(
  WalletsRepository walletsBloc,
  Map<String, dynamic> walletJson, {
  bool hasBackup = false,
}) async {
  final wallets = walletsBloc.wallets;
  final Wallet? existedDebugWallet = wallets?.firstWhereOrNull(
    (w) => w.name == walletJson['name'],
  );
  if (existedDebugWallet != null) return existedDebugWallet;

  final String name = walletJson['name'];
  final List<String> activatedCoins = List<String>.from(
    walletJson['activated_coins'] ?? <String>[],
  );

  return Wallet(
    id: const Uuid().v1(),
    name: name,
    config: WalletConfig(
      activatedCoins: activatedCoins,
      hasBackup: hasBackup,
      seedPhrase: walletJson['seed'],
    ),
  );
}

Future<List<dynamic>?> loadDebugSwaps() async {
  try {
    final testDataStr = await loadDebugWalletSource();
    if (testDataStr == null) return null;
    final Map<String, dynamic> debugDataJson = jsonDecode(testDataStr);
    if (debugDataJson['swaps'] == null) return null;
    return debugDataJson['swaps']['import'];
  } on Object {
    // A malformed local fixture must not print its wallet data in an error.
    return null;
  }
}
