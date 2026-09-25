import 'package:flutter/material.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';
import 'package:web_dex/views/wallets_manager/widgets/hardware_wallets_manager.dart';
import 'package:web_dex/views/wallets_manager/widgets/iguana_wallets_manager.dart';

class WalletsManager extends StatelessWidget {
  const WalletsManager({
    super.key,
    required this.eventType,
    required this.walletType,
    required this.close,
    required this.onSuccess,
    this.selectedWallet,
    this.initialHdMode = false,
    this.rememberMe = false,
    this.initialAction = WalletsManagerAction.none,
    this.initialWalletAction = WalletsManagerExistWalletAction.logIn,
  });
  final WalletsManagerEventType eventType;
  final WalletType walletType;
  final VoidCallback close;
  final Function(Wallet) onSuccess;
  final Wallet? selectedWallet;
  final bool initialHdMode;
  final bool rememberMe;

  /// Which form the iguana branch should open on. Defaults to none so existing
  /// callers - and `wallets_manager_test` - compile unchanged.
  final WalletsManagerAction initialAction;
  final WalletsManagerExistWalletAction initialWalletAction;

  @override
  Widget build(BuildContext context) {
    switch (walletType) {
      case WalletType.iguana:
      case WalletType.hdwallet:
        return IguanaWalletsManager(
          close: close,
          onSuccess: onSuccess,
          eventType: eventType,
          initialWallet: selectedWallet,
          initialHdMode: initialHdMode,
          rememberMe: rememberMe,
          initialAction: initialAction,
          initialWalletAction: initialWalletAction,
        );

      case WalletType.trezor:
        return HardwareWalletsManager(
          close: close,
          onSuccess: onSuccess,
          eventType: eventType,
        );
      case WalletType.keplr:
      case WalletType.metamask:
        return const SizedBox();
    }
  }
}
