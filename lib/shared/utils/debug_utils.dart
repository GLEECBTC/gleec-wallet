import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/model/wallet.dart';

Future<void> initDebugData(
  AuthBloc authBloc,
  WalletsRepository walletsRepository,
) async {
  try {
    final String testWalletStr = await rootBundle.loadString(
      'assets/debug_data.json',
    );
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
  final String? testDataStr;
  try {
    testDataStr = await rootBundle.loadString('assets/debug_data.json');
  } catch (e) {
    return null;
  }

  final Map<String, dynamic> debugDataJson = jsonDecode(testDataStr);

  if (debugDataJson['swaps'] == null) return null;
  return debugDataJson['swaps']['import'];
}
