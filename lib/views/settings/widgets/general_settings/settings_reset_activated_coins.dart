import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/dispatchers/popup_dispatcher.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';

class SettingsResetActivatedCoins extends StatefulWidget {
  const SettingsResetActivatedCoins({Key? key}) : super(key: key);

  @override
  State<SettingsResetActivatedCoins> createState() =>
      _SettingsResetActivatedCoinsState();
}

class _SettingsResetActivatedCoinsState
    extends State<SettingsResetActivatedCoins> {
  @override
  Widget build(BuildContext context) {
    return UiBorderButton(
      height: 32,
      borderWidth: 1,
      borderColor: theme.custom.specificButtonBorderColor,
      backgroundColor: theme.custom.specificButtonBackgroundColor,
      fontWeight: FontWeight.w500,
      text: LocaleKeys.debugSettingsResetActivatedCoins.tr(),
      icon: Icon(
        Icons.restart_alt,
        color: Theme.of(context).textTheme.bodyMedium?.color,
        size: 18,
      ),
      onPressed: _showResetPopup,
    );
  }

  Future<void> _showResetPopup() async {
    final walletsBloc = RepositoryProvider.of<WalletsRepository>(context);
    final wallets = await walletsBloc.getWallets();
    PopupDispatcher popupDispatcher = _createPopupDispatcher(wallets);
    popupDispatcher.show();
  }

  PopupDispatcher _createPopupDispatcher(List<Wallet> wallets) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    return PopupDispatcher(
      borderColor: theme.custom.specificButtonBorderColor,
      width: 320,
      popupContent: wallets.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  LocaleKeys.noWalletsAvailable.tr(),
                  style: textStyle,
                ),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  Text(LocaleKeys.selectWalletToReset.tr(), style: textStyle),
                  const SizedBox(height: 8),
                  ...List.generate(wallets.length, (index) {
                    return ListTile(
                      title: AutoScrollText(
                        text: wallets[index].name,
                        style: textStyle,
                      ),
                      onTap: () => _showConfirmationDialog(wallets[index]),
                    );
                  }),
                ],
              ),
            ),
    );
  }

  Future<void> _showConfirmationDialog(Wallet wallet) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(LocaleKeys.resetWalletTitle.tr()),
        content: SizedBox(
          width: 500,
          child: Text(LocaleKeys.resetWalletContent.tr(args: [wallet.name])),
        ),
        actions: [
          TextButton(
            child: Text(LocaleKeys.cancel.tr()),
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
          TextButton(
            child: Text(LocaleKeys.reset.tr()),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (result == true) {
      await _resetSpecificWallet(wallet);
    }
  }

  Future<void> _resetSpecificWallet(Wallet wallet) async {
    final walletsBloc = RepositoryProvider.of<WalletsRepository>(context);
    await walletsBloc.resetSpecificWallet(wallet);

    if (!mounted) return;

    // Show Dialog
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(LocaleKeys.resetCompleteTitle.tr()),
        content: Text(LocaleKeys.resetCompleteContent.tr(args: [wallet.name])),
        actions: [
          TextButton(
            child: Text(LocaleKeys.ok.tr()),
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        ],
      ),
    );
  }
}
