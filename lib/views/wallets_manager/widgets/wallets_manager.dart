import 'package:flutter/material.dart';
import 'package:web_dex/model/wallet.dart';
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
  });
  final WalletsManagerEventType eventType;
  final WalletType walletType;
  final VoidCallback close;
  final Function(Wallet) onSuccess;
  final Wallet? selectedWallet;
  final bool initialHdMode;
  final bool rememberMe;

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
