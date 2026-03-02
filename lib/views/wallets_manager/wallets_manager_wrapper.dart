import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallets_manager.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallets_type_list.dart';

class WalletsManagerWrapper extends StatefulWidget {
  const WalletsManagerWrapper({
    required this.eventType,
    this.onSuccess,
    this.selectedWallet,
    this.initialHdMode = false,
    this.rememberMe = false,
    this.onCancel,
    super.key = const Key('wallets-manager-wrapper'),
  });

  final Function(Wallet)? onSuccess;
  final WalletsManagerEventType eventType;
  final Wallet? selectedWallet;
  final bool initialHdMode;
  final bool rememberMe;
  final VoidCallback? onCancel;

  @override
  State<WalletsManagerWrapper> createState() => _WalletsManagerWrapperState();
}

class _WalletsManagerWrapperState extends State<WalletsManagerWrapper> {
  WalletType? _selectedWalletType;
  @override
  void initState() {
    super.initState();
    _selectedWalletType = widget.selectedWallet?.config.type;
  }

  @override
  Widget build(BuildContext context) {
    final WalletType? selectedWalletType = _selectedWalletType;
    if (selectedWalletType == null) {
      return Column(
        children: [
          Text(
            LocaleKeys.walletsTypeListTitle.tr(),
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontSize: 16),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 30.0),
            child: WalletsTypeList(onWalletTypeClick: _onWalletTypeClick),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 20.0),
            child: UiUnderlineTextButton(
              text: LocaleKeys.cancel.tr(),
              onPressed: _handleCancel,
            ),
          ),
        ],
      );
    }

    return WalletsManager(
      eventType: widget.eventType,
      walletType: selectedWalletType,
      close: _closeWalletManager,
      onSuccess: widget.onSuccess ?? (_) {},
      selectedWallet: widget.selectedWallet,
      initialHdMode: widget.selectedWallet?.config.type == WalletType.hdwallet
          ? true
          : widget.initialHdMode,
      rememberMe: widget.rememberMe,
    );
  }

  Future<void> _onWalletTypeClick(WalletType type) async {
    setState(() {
      _selectedWalletType = type;
    });
  }

  Future<void> _closeWalletManager() async {
    setState(() {
      _selectedWalletType = null;
    });
  }

  void _handleCancel() {
    final onCancel = widget.onCancel;
    if (onCancel != null) {
      onCancel();
      return;
    }
    Navigator.of(context).maybePop();
  }
}
